{ MQTT Client component for Free Pascal

  Copyright (C) 2022 Bernd Kreuß prof7bit@gmail.com

  This library is free software; you can redistribute it and/or modify it
  under the terms of the GNU Library General Public License as published by
  the Free Software Foundation; either version 2 of the License, or (at your
  option) any later version with the following modification:

  As a special exception, the copyright holders of this library give you
  permission to link this library with independent modules to produce an
  executable, regardless of the license terms of these independent modules,and
  to copy and distribute the resulting executable under terms of your choice,
  provided that you also meet, for each linked independent module, the terms
  and conditions of the license of that module. An independent module is a
  module which is not derived from or based on this library. If you modify
  this library, you may extend this exception to your version of the library,
  but you are not obligated to do so. If you do not wish to do so, delete this
  exception statement from your version.

  This program is distributed in the hope that it will be useful, but WITHOUT
  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
  FITNESS FOR A PARTICULAR PURPOSE. See the GNU Library General Public License
  for more details.

  You should have received a copy of the GNU Library General Public License
  along with this library; if not, write to the Free Software Foundation,
  Inc., 51 Franklin Street - Fifth Floor, Boston, MA 02110-1335, USA.
}
unit mqtt;

{$mode ObjFPC}{$H+}
{$ModeSwitch arrayoperators}

interface

uses
  Classes, sysutils, Sockets, SSockets, syncobjs, mqttinternal, fptimer,
  sslsockets, openssl, opensslsockets;

const
  MQTTDefaultKeepalive: UInt16        = 50; // seconds
  MQTTDefaultSessionExpiry: UInt32    = 60 * 60; // seconds
  MQTTPingTimeout: UInt16             = 10; // seconds

  // constants based on TDateTime (1 day = 1)
  HOUR = 1 / 24;
  MINUTE = HOUR / 60;
  SECOND = MINUTE / 60;

type
  TMQTTError = (
    mqeNoError = 0,
    mqeAlreadyConnected = 1,
    mqeNotConnected = 2,
    mqeHostNotFound = 3,
    mqeConnectFailed = 4,
    mqeInvalidTopicFilter = 5,
    mqeInvalidSubscriptionID = 6,
    mqeEmptyTopic = 7,
    mqeNotSubscribed = 8,
    mqeInvalidQoS = 9,
    mqeRetainUnavail = 10,
    mqeNotYetImplemented = 11,
    mqeSSLNotSupported = 12,
    mqeSSLVerifyError = 13,
    mqeCertFileNotFound = 14,
    mqeKeyFileNotFound = 15
  );

  TMQTTSocketWaitResult = (
    mqwrData,
    mqwrTimeout,
    mqwrError
  );

  TMQTTClient = class;
  TMQTTDebugFunc = procedure(Txt: String) of object;
  TMQTTConnectFunc = procedure(AClient: TMQTTClient) of object;
  TMQTTDisconnectFunc = procedure(AClient: TMQTTClient) of object;
  TMQTTReceiveFunc = procedure(AClient: TMQTTClient; ATopic, AMessage, AResponseTopic: String; ACorrelData: TBytes; ASubID: UInt32) of object;
  TMQTTVerifySSLFunc = procedure(AClient: TMQTTClient; ASSLHandler: TOpenSSLSocketHandler; var Allow: Boolean) of object;

  TTopicAlias = record
    ID: UInt16;
    Topic: String;
  end;

  TSubscriptionIDs = array of UInt32;

  TMQTTRXData = record
    ID: UInt16;
    Topic: String;
    Message: String;
    RespTopic: String;
    CorrelData: TBytes;
    SubscriptionIDs: TSubscriptionIDs;
  end;

  TMQTTQueuedPublish = record
    ID: UInt16;
    Topic: String;
    Message: String;
    ResponseTopic: String;
    CorrelData: TBytes;
    QoS: Byte;
    Retain: Boolean;
  end;

  TMQTTQueuedPubRel = record
    ID: uint16;
  end;

  TMQTTQueuedPubRec = record
    ID: uint16;
  end;

  TMQTTQueuedDebugMsg = record
    ID: UInt16;
    Txt: String;
  end;

  { TMQTTLockComponent }

  TMQTTLockComponent = class(TComponent)
  private
    FLock: TCriticalSection;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Lock;
    procedure Unlock;
  end;

  { TMQTTQueue }

  generic TMQTTQueue<T> = class(TMQTTLockComponent)
  private
    FClient: TMQTTClient;
    FName: String;
    FItems: array of T;
  public
    constructor Create(AClient: TMQTTClient; AName: String = ''); reintroduce;
    destructor Destroy; override;
    function Push(Item: T): Integer;
    function Pop(Out Item: T): Boolean;
    function Count: Integer;
    function Get(I: Integer): T;
    function Contains(ID: UInt16): Boolean;
    function Remove(ID: UInt16): Boolean;
    procedure Clear;
  end;

  TMQTTPublishQueue = specialize TMQTTQueue<TMQTTQueuedPublish>;
  TMQTTPubRelQueue = specialize TMQTTQueue<TMQTTQueuedPubRel>;
  TMQTTPubRecQueue = specialize TMQTTQueue<TMQTTQueuedPubRec>;
  TMQTTRxDataQueue = specialize TMQTTQueue<TMQTTRXData>;
  TMQTTDebugQueue = specialize TMQTTQueue<TMQTTQueuedDebugMsg>;

  { TMQTTSocket }

  TMQTTSocket = class(TInetSocket)
    FSSLHandler: TSSLSocketHandler;
    constructor CreateSSL(const AHost: String; APort: Word; Cert, Key: String);
    procedure Shutdown;
    function Wait: TMQTTSocketWaitResult;
  end;

  { TMQTTLIstenThread }

  TMQTTLIstenThread = class(TThread)
  protected
    Client: TMQTTClient;
    procedure Execute; override;
  public
    constructor Create(AClient: TMQTTClient); reintroduce;
  end;

  { TMQTTTopicAliases }

  TMQTTTopicAliases = class(TMQTTLockComponent)
  private
    FList: array of TTopicAlias;
  public
    function Handle(ID: UInt16; Topic: String): String;
    procedure Clear;
  end;

  { TMQTTClient }

  TMQTTClient = class(TMQTTLockComponent)
  protected
    FListenThread: TMQTTLIstenThread;
    FSocket: TMQTTSocket;
    FClosing: Boolean;
    FOnDebug: TMQTTDebugFunc;
    FOnConnect: TMQTTConnectFunc;
    FOnDisconnect: TMQTTDisconnectFunc;
    FOnVerifySSL: TMQTTVerifySSLFunc;
    FOnReceive: TMQTTReceiveFunc;
    FClientCert: String;
    FClientKey: String;
    FRXQueue: TMQTTRxDataQueue;
    FTopicAliases: TMQTTTopicAliases;
    FQueuedPublish: TMQTTPublishQueue;
    FQueuedPubRel: TMQTTPubRelQueue;
    FQueuedPubRec: TMQTTPubRecQueue;
    FDebugQueue: TMQTTDebugQueue;
    FListenWake: TEvent;
    FKeepalive: UInt16;
    FSessionExpiry: UInt32;
    FLastPing: TDateTime;
    FWaitingPingresp: Boolean;
    FKeepaliveTimer: TFPTimer;
    FNextPacketID: UInt16;
    FMaxQos: Byte;
    FRetainAvail: Boolean;
    FHost: String;
    FPort: Word;
    FClientID: String;
    FUserName: String;
    FPassword: String;
    FUseSSL: Boolean;
    procedure DebugSync;
    procedure Debug(Txt: String);
    procedure Debug(Txt: String; Args: array of const);
    procedure PushOnDisconnect;
    procedure PopOnDisconnect;
    procedure PushOnConnect;
    procedure PopOnConnect;
    procedure PushOnRX(PacketID: UInt16; Topic, Message, RespTopic: String; CorrelData: TBytes; SubIDs: TSubscriptionIDs);
    procedure popOnRX;
    procedure OnTimer(Sender: TObject);
    procedure Handle(P: TMQTTConnAck);
    procedure Handle(P: TMQTTPingResp);
    procedure Handle(P: TMQTTSubAck);
    procedure Handle(P: TMQTTPublish);
    procedure Handle(P: TMQTTDisconnect);
    procedure Handle(P: TMQTTUnsubAck);
    procedure Handle(P: TMQTTPubAck);
    procedure Handle(P: TMQTTPubRec);
    procedure Handle(P: TMQTTPubRel);
    procedure Handle(P: TMQTTPubComp);
    function GetNewPacketID: UInt16;
    function ConnectSocket(Host: String; Port: Word; SSL: Boolean): TMQTTError;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function Connect(Host: String; Port: Word; ID, User, Pass: String; SSL, CleanStart: Boolean): TMQTTError;
    function Disconnect: TMQTTError;
    function Subscribe(ATopicFilter: String; ASubsID: UInt32=0): TMQTTError;
    function Unsubscribe(ATopicFilter: String): TMQTTError;
    function Publish(Topic, Message, ResponseTopic: String; CorrelData: TBytes; QoS: Byte; Retain: Boolean): TMQTTError;
    function Connected: Boolean;
    property RetainAvail: Boolean read FRetainAvail;
    property MaxQoS: Byte read FMaxQos;
    property ClientCert: String read FClientCert write FClientCert;
    property ClientKey: String read FClientKey write FClientKey;
    property OnDebug: TMQTTDebugFunc read FOnDebug write FOnDebug;
    property OnDisconnect: TMQTTDisconnectFunc read FOnDisconnect write FOnDisconnect;
    property OnConnect: TMQTTConnectFunc read FOnConnect write FOnConnect;
    property OnVerifySSL: TMQTTVerifySSLFunc read FOnVerifySSL write FOnVerifySSL;
    property OnReceive: TMQTTReceiveFunc read FOnReceive write FOnReceive;
  end;

implementation
{$ifdef unix}
uses
  BaseUnix;

{$else}
uses
  WinSock2;

procedure fpFD_ZERO(out nset: TFDSet);
begin
  FD_ZERO(nset);
end;

procedure fpFD_SET(fdno: LongInt; var nset: TFDSet);
begin
  FD_SET(fdno, nset);
end;

function fpSelect(N: LongInt; readfds, writefds, exceptfds: pfdset; TimeOut: PTimeVal): LongInt;
begin
  Result := select(N, readfds, writefds, exceptfds, TimeOut);
end;

Function fpFD_ISSET (fdno: LongInt; var nset: TFDSet): LongInt;
begin
  Result := LongInt(FD_ISSET(fdno, nset));
end;
{$endif}

{ TMQTTLockComponent }

constructor TMQTTLockComponent.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FLock := TCriticalSection.Create;
end;

destructor TMQTTLockComponent.Destroy;
begin
  FLock.Free;
  inherited Destroy;
end;

procedure TMQTTLockComponent.Lock;
begin
  FLock.Acquire;
end;

procedure TMQTTLockComponent.Unlock;
begin
  FLock.Release;
end;

{ TMQTTTopicAliases }

function TMQTTTopicAliases.Handle(ID: UInt16; Topic: String): String;
var
  I: Integer;
  A: TTopicAlias;
begin
  Result := Topic;
  Lock;
  try
    if ID > 0 then
      if Topic <> '' then begin // both are set
        // either find existing and update it...
        for I := 0 to Length(FList) - 1 do begin
          if FList[I].ID = ID then begin
            FList[I].Topic := Topic;
            exit(Topic);
          end
        end;
        // ...or add a new alias to the list
        A.ID := ID;
        A.Topic := Topic;
        FList += [A];
      end
      else // only ID is set: look up topic name
        for A in FList do
          if A.ID = ID then
            exit(A.Topic);
  finally
    Unlock;
  end;
end;

procedure TMQTTTopicAliases.Clear;
begin
  Lock;
  try
    FList := [];
  finally
    Unlock;
  end;
end;

{ TMQTTlist }

constructor TMQTTQueue.Create(AClient: TMQTTClient; AName: String);
begin
  inherited Create(AClient);
  FClient := AClient;
  FName := AName;
end;

destructor TMQTTQueue.Destroy;
begin
  inherited Destroy;
end;

function TMQTTQueue.Push(Item: T): Integer;
begin
  Lock;
  try
    FItems += [Item];
    Result := Length(FItems);
    if FName <> '' then
      FClient.Debug('%s queue: pushed ID %d, new count %d', [FName, Item.ID, Length(FItems)]);
  finally
    Unlock;
  end;
end;

function TMQTTQueue.Pop(out Item: T): Boolean;
begin
  Result := False;
  Lock;
  try
    if Length(FItems) > 0 then begin
      Item := FItems[0];
      Delete(FItems, 0, 1);
      Result := True;
      if FName <> '' then
        FClient.Debug('%s queue: popped ID %d, new count %d', [FName, Item.ID, Length(FItems)]);
    end
    else
      if FName <> '' then
        FClient.Debug('%s queue: nothing more to pop', [FName, Item.ID, Length(FItems)]);
  finally
    Unlock;
  end;
end;

function TMQTTQueue.Count: Integer;
begin
  Lock;
  try
    Result := Length(FItems);
  finally
    Unlock;
  end;
end;

function TMQTTQueue.Get(I: Integer): T;
begin
  Lock;
  try
    Result := FItems[I];
  finally
    Unlock;
  end;
end;

function TMQTTQueue.Contains(ID: UInt16): Boolean;
var
  I: Integer;
begin
  Result := False;
  Lock;
  try
    For I := 0 to Length(FItems) - 1 do
      if FItems[I].ID = ID then
        exit(True);
  finally
    Unlock;
  end;
end;

function TMQTTQueue.Remove(ID: UInt16): Boolean;
var
  I: Integer;
begin
  Result := False;
  Lock;
  try
    for I := 0 to Length(FItems) - 1 do begin
      if FItems[I].ID = ID then begin
        Delete(FItems, I, 1);
        if FName <> '' then
          FClient.Debug('%s queue: removed ID %d, new count %d', [FName, ID, Length(FItems)]);
        exit(True);
      end;
    end;
  finally
    Unlock;
  end;
  if FName <> '' then
    FClient.Debug('%s queue: ID %d not found, count %d', [FName, ID, Length(FItems)]);
end;

procedure TMQTTQueue.Clear;
begin
  Lock;
  try
    FItems := [];
  finally
    Unlock;
  end;
end;

{ TMQTTSocket }

constructor TMQTTSocket.CreateSSL(const AHost: String; APort: Word; Cert, Key: String);
begin
  FSSLHandler := TSSLSocketHandler.GetDefaultHandler;
  FSSLHandler.CertificateData.Certificate.FileName := Cert;
  FSSLHandler.CertificateData.PrivateKey.FileName := Key;
  Inherited Create(AHost, APort, FSSLHandler);
  Connect;
end;

procedure TMQTTSocket.Shutdown;
begin
  if Assigned(FSSLHandler) then
    FSSLHandler.Shutdown(True)
  else
    fpshutdown(Handle, SHUT_RDWR);
end;

function TMQTTSocket.Wait: TMQTTSocketWaitResult;
var
  RS, ES: TFDSet;
  TV: TTimeVal;
  Sel: Integer;
begin
  // when using ssl we must first check available bytes in the ssl handler
  // before waiting on the underlying socket, because when data has already
  // arrived and already been decrypted but not yet completely read we won't
  // see anything being signaled on the underlying socket anymore.
  if Assigned(FSSLHandler) then
    if FSSLHandler.BytesAvailable > 0 then
      exit(mqwrData);

  fpFD_ZERO(RS);
  fpFD_SET(Handle, RS);
  fpFD_ZERO(ES);
  fpFD_SET(Handle, ES);
  TV.tv_sec := 0;
  TV.tv_usec := 500000;
  Sel := fpSelect(Handle + 1, @RS, nil, @ES, @TV);
  if Sel = 0 then
    Result := mqwrTimeout
  else if fpFD_ISSET(Handle, RS) > 0 then
    Result := mqwrData
  else
    Result := mqwrError;
end;

{ TMQTTLIstenThread }

procedure TMQTTLIstenThread.Execute;
var
  P: TMQTTParsedPacket;
  WR: TMQTTSocketWaitResult;

begin
  repeat
    if Client.Connected and not Client.FClosing then begin
      try
        WR := Client.FSocket.Wait;
        if Client.FClosing then
          Client.Debug('wait() returned, socket was closed locally')
        else begin
          case WR of
            mqwrTimeout: begin
              // nothing
            end;
            mqwrError: begin
              Client.Debug('wait() returned error, closing connection');
              Client.Disconnect;
            end;
            mqwrData: begin
              P := Client.FSocket.ReadMQTTPacket;
              // Client.Debug('RX: %s %s', [P.ClassName, P.DebugPrint(True)]);

              // The order of the if branches below matters because some classes
              // are subclasses of others, we need to check for the most specialized
              // class first because the is operator detects any anchestor also!
              // Therefore here in reverse order of declaration.
              if      P is TMQTTDisconnect  then Client.Handle(P as TMQTTDisconnect)
              else if P is TMQTTPingResp    then Client.Handle(P as TMQTTPingResp)
              else if P is TMQTTUnsubAck    then Client.Handle(P as TMQTTUnsubAck)
              else if P is TMQTTSubAck      then Client.Handle(P as TMQTTSubAck)
              else if P is TMQTTPubComp     then Client.Handle(P as TMQTTPubComp)
              else if P is TMQTTPubRel      then Client.Handle(P as TMQTTPubRel)
              else if P is TMQTTPubRec      then Client.Handle(P as TMQTTPubRec)
              else if P is TMQTTPubAck      then Client.Handle(P as TMQTTPubAck)
              else if P is TMQTTPublish     then Client.Handle(P as TMQTTPublish)
              else if P is TMQTTConnAck     then Client.Handle(P as TMQTTConnAck)
              else begin
                Client.Debug('<- unknown packet type %d flags %d', [P.PacketType, P.PacketFlags]);
                Client.Debug('   data %s', [P.DebugPrint(True)]);
              end;
              P.Free;
            end;
          end;
        end

      except
        on E: Exception do begin
          writeln('read raised error');
          Client.Debug('%s: %s', [E.ClassName, E.Message]);
          Client.Disconnect;
        end;
      end;
    end
    else
      Client.FListenWake.WaitFor(INFINITE);
  until Terminated;
end;

constructor TMQTTLIstenThread.Create(AClient: TMQTTClient);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  Client := AClient;
  Start;
end;

{ TMQTTClient }

procedure TMQTTClient.DebugSync;
var
  Msg: TMQTTQueuedDebugMsg;
begin
  if Assigned(FOnDebug) then
    while FDebugQueue.Pop(Msg) do
      FOnDebug(Msg.Txt);
end;

procedure TMQTTClient.Debug(Txt: String);
var
  Msg: TMQTTQueuedDebugMsg;
begin
  if not Assigned(FOnDebug) then
    exit;
  Msg.Txt := '[mqtt debug] ' + Txt;
  FDebugQueue.Push(Msg);
  TThread.Synchronize(nil, @DebugSync);
end;

procedure TMQTTClient.Debug(Txt: String; Args: array of const);
begin
  if not Assigned(FOnDebug) then
    exit;
  Debug(Format(Txt, Args));
end;

procedure TMQTTClient.PushOnDisconnect;
begin
  TThread.Queue(nil, @PopOnDisconnect);
end;

procedure TMQTTClient.PopOnDisconnect;
begin
  // called from the main thread event loop
  if Assigned(FOnDisconnect) then
    FOnDisconnect(self);
end;

procedure TMQTTClient.PushOnConnect;
begin
  TThread.Queue(nil, @PopOnConnect);
end;

procedure TMQTTClient.PopOnConnect;
begin
  // called from the main thread event loop
  if Assigned(FOnConnect) then
    FOnConnect(self);
end;

procedure TMQTTClient.PushOnRX(PacketID: UInt16; Topic, Message, RespTopic: String; CorrelData: TBytes; SubIDs: TSubscriptionIDs);
var
  Data: TMQTTRXData;
begin
  Data.ID := PacketID;
  Data.Topic := Topic;
  Data.Message := Message;
  Data.RespTopic := RespTopic;
  Data.CorrelData := CorrelData;
  Data.SubscriptionIDs := SubIDs;
  FRXQueue.Push(Data);
  TThread.Queue(nil, @popOnRX);
end;

procedure TMQTTClient.popOnRX;
var
  Data: TMQTTRXData;
  ID: Uint32;
begin
  if FRXQueue.Pop(Data) then begin
    if Assigned(FOnReceive) then begin
      if Length(Data.SubscriptionIDs) = 0 then begin
        FOnReceive(Self, Data.Topic, Data.Message, Data.RespTopic, Data.CorrelData, 0)
      end
      else begin
        for ID in Data.SubscriptionIDs do begin
          FOnReceive(Self, Data.Topic, Data.Message, Data.RespTopic, Data.CorrelData, ID);
        end;
      end;
    end;
  end;
end;

procedure TMQTTClient.OnTimer(Sender: TObject);
begin
  if Connected then begin
    if Now - FLastPing > FKeepalive * SECOND then begin
      Debug('-> pingreq');
      FWaitingPingresp := True;
      FLastPing := Now;
      FSocket.WriteMQTTPingReq;
    end;
    if FWaitingPingresp and (Now - FLastPing > MQTTPingTimeout * SECOND) then begin
      Debug('ping timeout, trying to reconnect');
      Disconnect;
      Connect(FHost, FPort, FClientID, FUsername, FPassword, FUseSSL, False);
    end;
  end;
end;

procedure TMQTTClient.Handle(P: TMQTTConnAck);
var
  I: Integer;
  QPublish: TMQTTQueuedPublish;
  QPubRel: TMQTTQueuedPubRel;
  QPubRec: TMQTTQueuedPubRec;
begin
  if (P.ServerKeepalive > 0) and (P.ServerKeepalive < FKeepalive) then
    FKeepalive := P.ServerKeepalive;
  if (P.SessionExpiry > 0) and  (P.SessionExpiry < FSessionExpiry) then
    FSessionExpiry := P.SessionExpiry;
  FMaxQos := P.MaxQoS;
  FRetainAvail := P.RetainAvail;
  Debug('<- connack');
  Debug('   keepalive is %d seconds', [FKeepalive]);
  Debug('   session expiry is %d seconds', [FSessionExpiry]);
  Debug('   topic alias max is %d', [P.TopicAliasMax]);
  Debug('   max QoS is %d', [FMaxQoS]);
  Debug('   retain available: %s', [BoolToStr(FRetainAvail, 'yes', 'no')]);
  Debug('connected.');
  if P.ReasonCode = 0 then begin
    FQueuedPublish.Lock;
    try
      for I := 0 to FQueuedPublish.Count - 1 do begin
        QPublish := FQueuedPublish.Get(I);
        Debug('-> publish (unacked), PacketID %d', [QPublish.ID]);
        FSocket.WriteMQTTPublish(QPublish.Topic, QPublish.Message, QPublish.ResponseTopic, QPublish.CorrelData, QPublish.ID, QPublish.QoS, QPublish.Retain, True);
      end;
    finally
      FQueuedPublish.Unlock;
    end;

    FQueuedPubRec.Lock;
    try
      for I := 0 to FQueuedPubRec.Count - 1 do begin
        QPubRec := FQueuedPubRec.Get(I);
        Debug('-> pubrec (unacked), PacketID %d', [QPubRec.ID]);
        FSocket.WriteMQTTPubRec(QPubRec.ID, 0);
      end;
    finally
      FQueuedPubRec.Unlock;
    end;

    FQueuedPubRel.Lock;
    try
      for I := 0 to FQueuedPubRel.Count - 1 do begin
        QPubRel := FQueuedPubRel.Get(I);
        Debug('-> pubrel (unacked), PacketID %d', [QPubRel.ID]);
        FSocket.WriteMQTTPubRel(QPubRec.ID, 0);
      end;
    finally
      FQueuedPubRel.Unlock;
    end;
  end;
  PushOnConnect;
end;

procedure TMQTTClient.Handle(P: TMQTTPingResp);
begin
  Debug('<- pingresp');
  FWaitingPingresp := False;
end;

procedure TMQTTClient.Handle(P: TMQTTSubAck);
var
  B: Byte;
  S: String;
begin
  Debug('<- suback PacketID: %d', [P.PacketID]);
  if Assigned(FOnDebug) then begin
    S := '   suback ReasonCode(s): ';
    for B in P.ReasonCodes do begin
      S += IntToHex(B, 2) + ' ';
    end;
    Debug(S)
  end;
end;

procedure TMQTTClient.Handle(P: TMQTTPublish);
var
  Topic: String;
  UsingAlias: Boolean;
  PubRec: TMQTTQueuedPubRec;
  Duplication: Boolean = False;

begin
  Topic := FTopicAliases.Handle(P.TopicAlias, P.TopicName);
  UsingAlias := (P.TopicAlias > 0) and (P.TopicName = '');
  Debug('<- publish, PacketID: %d, alias: %s, QoS: %d, topic: %s, message: %s',
   [P.PacketID, BoolToStr(UsingAlias, 'yes', 'no'), P.QoS, Topic, P.Message]);

  // prevent duplication in QoS 2
  if (P.QoS = 2) and FQueuedPubRec.Contains(P.PacketID) then begin
    Debug('QoS 2 duplicated publish detected, not calling app callback again');
    Duplication := True;
  end;

  if not Duplication then
    PushOnRX(P.PacketID, Topic, P.Message, P.RespTopic, P.CorrelData, P.SubscriptionID);

  if P.QoS = 1 then begin
    Debug('-> puback, PacketID %d', [P.PacketID]);
    FSocket.WriteMQTTPubAck(P.PacketID, 0);
  end

  else if P.QoS = 2 then begin
    PubRec.ID := P.PacketID;
    if not Duplication then
      FQueuedPubRec.Push(PubRec);
    Debug('-> pubrec, PacketID %d', [P.PacketID]);
    FSocket.WriteMQTTPubRec(PubRec.ID, 0);
  end;
end;

procedure TMQTTClient.Handle(P: TMQTTDisconnect);
begin
  Debug('<- disconnect, ReasonCode %d %s', [P.ReasonCode, P.ReasonString]);
  Disconnect;
end;

procedure TMQTTClient.Handle(P: TMQTTUnsubAck);
var
  ReasonCode: Byte;
begin
  for ReasonCode in P.ReasonCodes do
    Debug('<- unsuback, ReasonCode %d', [ReasonCode]);
end;

procedure TMQTTClient.Handle(P: TMQTTPubAck);
begin
  Debug('<- puback, PacketID %d, ReasonCode %d', [P.PacketID, P.ReasonCode]);
  FQueuedPublish.Remove(P.PacketID);
end;

procedure TMQTTClient.Handle(P: TMQTTPubRec);
var
  PubRel: TMQTTQueuedPubRel;
begin
  Debug('<- pubrec, PacketID %d', [P.PacketID]);
  PubRel.ID := P.PacketID;
  FQueuedPubRel.Push(PubRel);
  Debug('-> pubrel, PacketID %d', [P.PacketID]);
  FSocket.WriteMQTTPubRel(P.PacketID, 0);
  FQueuedPublish.Remove(P.PacketID);
end;

procedure TMQTTClient.Handle(P: TMQTTPubRel);
begin
  Debug('<- pubrel, PacketID %d', [P.PacketID]);
  Debug('-> pubcomp, PacketID %d', [P.PacketID]);
  FSocket.WriteMQTTPubComp(P.PacketID, 0);
  FQueuedPubRec.Remove(P.PacketID);
end;

procedure TMQTTClient.Handle(P: TMQTTPubComp);
begin
  Debug('<- pubcomp, PacketID %d', [P.PacketID]);
  FQueuedPubRel.Remove(P.PacketID);
end;

function TMQTTClient.GetNewPacketID: UInt16;
begin
  // fixme
  Lock;
  try
    Result := FNextPacketID;
    if Result = 0 then // IDs must be non-zero, so we skip the zero
      Result := 1;
    FNextPacketID := Result + 1;
  finally
    Unlock;
  end;
end;

function TMQTTClient.ConnectSocket(Host: String; Port: Word; SSL: Boolean): TMQTTError;
var
  Allow: Boolean = True;
  S: TMQTTSocket;
begin
  if Connected then
    exit(mqeAlreadyConnected);

  if ClientCert <> '' then
    if not FileExists(ClientCert) then
      exit(mqeCertFileNotFound);

  if ClientKey <> '' then
    if not FileExists(ClientKey) then
      exit(mqeKeyFileNotFound);

  FClosing := False;
  try
    if SSL then begin
      {$ifndef windows}
      if not InitSSLInterface then begin
        Debug('ssl version 1.x not found, trying version 3');
        openssl.DLLVersions[1] := '.3';
      end;
      {$endif}
      if not InitSSLInterface then begin
        Debug('ssl not supported');
        exit(mqeSSLNotSupported);
      end;
      S := TMQTTSocket.CreateSSL(Host, Port, FClientCert, FClientKey);
      if Assigned(FOnVerifySSL) then begin
        FOnVerifySSL(Self, S.FSSLHandler as TOpenSSLSocketHandler, Allow);
        if not Allow then begin
          S.Free;
          exit(mqeSSLVerifyError);
        end;
      end;
      FSocket := S;
    end
    else begin
      FSocket := TMQTTSocket.Create(Host, Port); // connect is implicit without ssl
    end;
    FListenWake.SetEvent;
    Result := mqeNoError;
  except
    on E: ESocketError do begin
      if E.Code = seHostNotFound then
        Result := mqeHostNotFound
      else
        Result := mqeConnectFailed;
      FSocket := nil;
    end;
  end;
end;

constructor TMQTTClient.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FMaxQos := 2;
  FQueuedPublish := TMQTTPublishQueue.Create(Self, 'publish');
  FQueuedPubRel := TMQTTPubRelQueue.Create(Self, 'pubrel');
  FQueuedPubRec := TMQTTPubRecQueue.Create(Self, 'pubrec');
  FRXQueue := TMQTTRxDataQueue.Create(Self);
  FDebugQueue := TMQTTDebugQueue.Create(Self);
  FTopicAliases :=  TMQTTTopicAliases.Create(Self);
  FListenWake := TEventObject.Create(nil, False, False, '');
  FSocket := nil;
  FListenThread := TMQTTLIstenThread.Create(Self);
  FKeepaliveTimer := TFPTimer.Create(Self);
  FKeepaliveTimer.OnTimer := @OnTimer;
  FKeepaliveTimer.Interval := 1000;
  FKeepaliveTimer.Enabled := True;
end;

destructor TMQTTClient.Destroy;
begin
  FOnDisconnect := nil;
  FListenThread.Terminate;
  FListenWake.SetEvent;
  if Connected then
    Disconnect;
  FListenThread.WaitFor;
  FListenThread.Free;
  FreeAndNil(FListenWake);
  inherited Destroy;
end;

function TMQTTClient.Connect(Host: String; Port: Word; ID, User, Pass: String; SSL, CleanStart: Boolean): TMQTTError;
begin
  FHost := Host;
  FPort := Port;
  FClientID := ID;
  FUserName := User;
  FPassword := Pass;
  FUseSSL := SSL;
  FLastPing := Now;
  FWaitingPingresp := False;
  Result := ConnectSocket(Host, Port, SSL);
  if Result = mqeNoError then begin
    FKeepalive := MQTTDefaultKeepalive;
    FSessionExpiry := MQTTDefaultSessionExpiry;
    Debug('-> connect');
    FSocket.WriteMQTTConnect(ID, User, Pass, FKeepalive, CleanStart, FSessionExpiry);
    FLastPing := Now;
  end;
end;

function TMQTTClient.Disconnect: TMQTTError;
begin
  if not Connected then
    exit(mqeNotConnected);

  Debug('disconnect');
  FClosing := True;
  FSocket.Shutdown;
  FSocket.Free;
  FSocket := nil;
  FRXQueue.Clear;
  FTopicAliases.Clear;
  PushOnDisconnect;
  Result := mqeNoError;
end;

function TMQTTClient.Subscribe(ATopicFilter: String; ASubsID: UInt32): TMQTTError;
begin
  Result := mqeNoError;
  if not Connected then
    exit(mqeNotConnected);

  if ASubsID >= $0fffffff {Ch. 3.8.2.1.2} then
    exit(mqeInvalidSubscriptionID);

  // if the subscription ID is 0 then it will send a packet without ID
  // entirely. Resulting received messages without subscription ID will
  // then also consequentky call the OnReceive handler with ID set to 0.
  // So the app can entirely ignore all this subscription ID business by
  // always using ID = 0 and it will work like in older protocol versions.
  Debug('-> subscribe, topic %s, SubsID %d', [ATopicFilter, ASubsID]);
  FSocket.WriteMQTTSubscribe(ATopicFilter, GetNewPacketID, ASubsID);
end;

function TMQTTClient.Unsubscribe(ATopicFilter: String): TMQTTError;
begin
  Result := mqeNoError;
  if not connected then
    exit(mqeNotConnected);

  if ATopicFilter <> '' then begin
    Debug('-> unsubscribe, topic %s', [ATopicFilter]);
    FSocket.WriteMQTTUnsubscribe(ATopicFilter, GetNewPacketID);
  end
  else
    Exit(mqeInvalidTopicFilter);
end;

function TMQTTClient.Publish(Topic, Message, ResponseTopic: String; CorrelData: TBytes; QoS: Byte; Retain: Boolean): TMQTTError;
var
  PacketID: UInt16;
  M: TMQTTQueuedPublish;
begin
  Result := mqeNoError;
  if not Connected then
    exit(mqeNotConnected);

  if QoS > FMaxQos then  // set by the server in CONNACK
    exit(mqeInvalidQoS);

  if Retain and not FRetainAvail then // set by server in CONNACK
    exit(mqeRetainUnavail);

  PacketID := GetNewPacketID;
  if QoS > 0 then begin
    M.ID := PacketID;
    M.Topic := Topic;
    M.Message := Message;
    M.ResponseTopic := ResponseTopic;
    M.CorrelData := CorrelData;
    M.QoS := QoS;
    M.Retain := Retain;
    FQueuedPublish.Push(M);
  end;
  Debug('-> publish, PacketID %d', [PacketID]);
  FSocket.WriteMQTTPublish(Topic, Message, ResponseTopic, CorrelData, PacketID, QoS, Retain, False);
end;

function TMQTTClient.Connected: Boolean;
begin
  Result := Assigned(FSocket) and not FClosing;
end;


end.

