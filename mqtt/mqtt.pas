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
  Classes, sysutils, Sockets, SSockets, syncobjs, mqttinternal, fptimer;

const
  MQTTDefaultKeepalive: UInt16 = 120; // seconds

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
    mqeMissingHandler = 5,
    mqeAlreadySubscribed = 6,
    mqeEmptyTopic = 7,
    mqeNotSubscribed = 8,
    mqeInvalidQoS = 9,
    mqeRetainUnavail = 10,
    mqeNotYetImplemented = 11
  );

  TMQTTClient = class;
  TMQTTDebugFunc = procedure(Txt: String) of object;
  TMQTTConnectFunc = procedure(AClient: TMQTTClient) of object;
  TMQTTDisconnectFunc = procedure(AClient: TMQTTClient) of object;
  TMQTTRXFunc = procedure(AClient: TMQTTClient; ATopic, AMessage, AResponseTopic: String; ACorrelData: TBytes) of object;

  TMQTTSubscriptionInfo = record
    TopicFilter: String;
    SubID: UInt32;
    Handler: TMQTTRXFunc;
  end;

  TTopicAlias = record
    ID: UInt16;
    Topic: String;
  end;

  TMQTTRXData = record
    Topic: String;
    Message: String;
    RespTopic: String;
    CorrelData: TBytes;
    Handler: TMQTTRXFunc;
  end;

  { TMQTTLIstenThread }

  TMQTTLIstenThread = class(TThread)
  protected
    Client: TMQTTClient;
    procedure Execute; override;
  public
    constructor Create(AClient: TMQTTClient); reintroduce;
  end;

  { TMQTTClient }

  TMQTTClient = class(TComponent)
  protected
    FListenThread: TMQTTLIstenThread;
    FSocket: TInetSocket;
    FClosing: Boolean;
    FOnDebug: TMQTTDebugFunc;
    FOnConnect: TMQTTConnectFunc;
    FOnDisconnect: TMQTTDisconnectFunc;
    FSubInfos: array of TMQTTSubscriptionInfo;
    FRXQueue: array of TMQTTRXData;
    FTopicAliases: array of TTopicAlias;
    FDebugTxt: String;
    FLock: TCriticalSection;
    FListenWake: TEvent;
    FKeepalive: UInt16;
    FLastPing: TDateTime;
    FKeepaliveTimer: TFPTimer;
    FNextPacketID: UInt16;
    FNextSubsID: UInt64;
    FMaxQos: Byte;
    FRetainAvail: Boolean;
    procedure DebugSync;
    procedure Debug(Txt: String);
    procedure Debug(Txt: String; Args: array of const);
    procedure PushOnDisconnect;
    procedure PopOnDisconnect;
    procedure PushOnConnect;
    procedure PopOnConnect;
    procedure PushOnRX(Subscription: TMQTTSubscriptionInfo; Topic, Message, RespTopic: String; CorrelData: TBytes);
    procedure popOnRX;
    procedure OnTimer(Sender: TObject);
    procedure Handle(P: TMQTTConnAck);
    procedure Handle(P: TMQTTPingResp);
    procedure Handle(P: TMQTTSubAck);
    procedure Handle(P: TMQTTPublish);
    procedure Handle(P: TMQTTDisconnect);
    procedure Handle(P: TMQTTUnsubAck);
    function GetNewPacketID: UInt16;
    function GetNewSubsID: UInt32;
    function ConnectSocket(Host: String; Port: Word): TMQTTError;
    function GetSubInfo(SubID: UInt32): TMQTTSubscriptionInfo;
    function GetSubInfo(TopicFilter: String): TMQTTSubscriptionInfo;
    function HandleTopicAlias(ID: UInt16; Topic: String): String;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function Connect(Host: String; Port: Word; ID, User, Pass: String): TMQTTError;
    function Disconect: TMQTTError;
    function Subscribe(ATopicFilter: String; AHandler: TMQTTRXFunc): TMQTTError;
    function Unsubscribe(ATopicFilter: String): TMQTTError;
    function Publish(Topic, Message, ResponseTopic: String; CorrelData: TBytes; QoS: Byte; Retain: Boolean): TMQTTError;
    function Connected: Boolean;
    property RetainAvail: Boolean read FRetainAvail;
    property MaxQoS: Byte read FMaxQos;
    property OnDebug: TMQTTDebugFunc read FOnDebug write FOnDebug;
    property OnDisconnect: TMQTTDisconnectFunc read FOnDisconnect write FOnDisconnect;
    property OnConnect: TMQTTConnectFunc read FOnConnect write FOnConnect;
  end;

implementation

{ TMQTTLIstenThread }

procedure TMQTTLIstenThread.Execute;
var
  P: TMQTTParsedPacket;
begin
  repeat
    if Client.Connected then begin
      try
        P := Client.FSocket.ReadMQTTPacket;
        // Client.Debug('RX: %s %s', [P.ClassName, P.DebugPrint(True)]);
        if      P is TMQTTConnAck     then Client.Handle(P as TMQTTConnAck)
        else if P is TMQTTPingResp    then Client.Handle(P as TMQTTPingResp)
        else if P is TMQTTSubAck      then Client.Handle(P as TMQTTSubAck)
        else if P is TMQTTPublish     then Client.Handle(P as TMQTTPublish)
        else if P is TMQTTDisconnect  then Client.Handle(P as TMQTTDisconnect)
        else if P is TMQTTUnsubAck    then Client.Handle(P as TMQTTUnsubAck)
        else begin
          Client.Debug('RX: unknown packet type %d flags %d', [P.PacketType, P.PacketFlags]);
          Client.Debug('RX: data %s', [P.DebugPrint(True)]);
        end;
        P.Free;
      except
        on E: Exception do begin
          if not Client.FClosing then begin
            Client.Debug('%s: %s', [E.ClassName, E.Message]);
            Client.Disconect;
          end;
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
  FreeOnTerminate := True;
  Client := AClient;
  Start;
end;

{ TMQTTClient }

procedure TMQTTClient.DebugSync;
begin
  if Assigned(FOnDebug) then
    FOnDebug(FDebugTxt)
  else
    Writeln(FDebugTxt);
end;

procedure TMQTTClient.Debug(Txt: String);
begin
  if not Assigned(FOnDebug) then
    exit;
  FDebugTxt := '[mqtt debug] ' + Txt;
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

procedure TMQTTClient.PushOnRX(Subscription: TMQTTSubscriptionInfo; Topic, Message, RespTopic: String; CorrelData: TBytes);
var
  Data: TMQTTRXData;
begin
  Data.Topic := Topic;
  Data.Message := Message;
  Data.RespTopic := RespTopic;
  Data.CorrelData := CorrelData;
  Data.Handler := Subscription.Handler;
  FLock.Acquire;
  FRXQueue := [Data] + FRXQueue;
  FLock.Release;
  TThread.Queue(nil, @popOnRX);
end;

procedure TMQTTClient.popOnRX;
var
  I: Integer;
  Data: TMQTTRXData;
begin
  // called from the main thread event loop
  FLock.Acquire;
  I := Length(FRXQueue) - 1;
  if I < 0 then
    FLock.Release
  else begin
    Data := FRXQueue[I];
    SetLength(FRXQueue, I);
    FLock.Release;
    if Assigned(Data.Handler) then
      Data.Handler(Self, Data.Topic, Data.Message, Data.RespTopic, Data.CorrelData);
  end;
end;

procedure TMQTTClient.OnTimer(Sender: TObject);
begin
  if Connected then begin
    if Now - FLastPing > FKeepalive * SECOND then begin
      Debug('ping');
      FSocket.WriteMQTTPingReq;
      FLastPing := Now;
    end;
  end;
end;

procedure TMQTTClient.Handle(P: TMQTTConnAck);
begin
  if P.ServerKeepalive < FKeepalive then
    FKeepalive := P.ServerKeepalive;
  FMaxQos := P.MaxQoS;
  FRetainAvail := P.RetainAvail;
  Debug('keepalive is %d seconds', [FKeepalive]);
  Debug('topic alias max is %d', [P.TopicAliasMax]);
  Debug('max QoS is %d', [FMaxQoS]);
  Debug('retain available: %s', [BoolToStr(FRetainAvail, 'yes', 'no')]);
  Debug('connected.');
  PushOnConnect;
end;

procedure TMQTTClient.Handle(P: TMQTTPingResp);
begin
  Debug('pong');
end;

procedure TMQTTClient.Handle(P: TMQTTSubAck);
var
  B: Byte;
  S: String;
begin
  Debug('suback PacketID: %d', [P.PacketID]);
  Debug('suback ReasonString: ' + P.ReasonString);
  S := 'suback ReasonCodes: ';
  for B in P.ReasonCodes do begin
    S += IntToHex(B, 2) + ' ';
  end;
  Debug(S)
end;

procedure TMQTTClient.Handle(P: TMQTTPublish);
var
  SubID: UInt32;
  SubInfo: TMQTTSubscriptionInfo;
  Topic: String;
begin
  Topic := HandleTopicAlias(P.TopicAlias, P.TopicName);
  for SubID in P.SubscriptionID do begin
    SubInfo := GetSubInfo(SubID);
    if Assigned(SubInfo.Handler) then begin
      Debug('publish: fltr: %s tpc: %s msg: %s, QoS: %d, Retain: %s',
        [SubInfo.TopicFilter, Topic, P.Message, P.QoS, BoolToStr(P.Retain, True)]);
      PushOnRX(SubInfo, Topic, P.Message, P.RespTopic, P.CorrelData);
    end
    else
      Debug('BUG! cannot find subscription handler for ID %d, this should never happen! (Topic: %s)',
        [SubID, Topic]);
  end;
end;

procedure TMQTTClient.Handle(P: TMQTTDisconnect);
begin
  Debug('disconnect: reason %d %s', [P.ReasonCode, P.ReasonString]);
  Disconect;
end;

procedure TMQTTClient.Handle(P: TMQTTUnsubAck);
var
  ReasonCode: Byte;
begin
  for ReasonCode in P.ReasonCodes do
    Debug('unsuback reason code: %d', [ReasonCode]);
end;

function TMQTTClient.GetNewPacketID: UInt16;
begin
  FLock.Acquire;
  Result := FNextPacketID;
  if Result = 0 then // IDs must be non-zero, so we skip the zero
    Result := 1;
  FNextPacketID := Result + 1;
  FLock.Release;
end;

function TMQTTClient.GetNewSubsID: UInt32;
begin
  FLock.Acquire;
  Result := FNextSubsID;
  if Result = 0 then // IDs must be non-zero, so we skip the zero
    Result := 1;
  FNextSubsID := Result + 1;
  FLock.Release;
end;

function TMQTTClient.ConnectSocket(Host: String; Port: Word): TMQTTError;
begin
  if Connected then
    Result := mqeAlreadyConnected
  else begin
    FClosing := False;
    try
      FSocket := TInetSocket.Create(Host, Port);
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
end;

function TMQTTClient.GetSubInfo(SubID: UInt32): TMQTTSubscriptionInfo;
begin
  for Result in FSubInfos do
    if Result.SubID = SubID then
      exit;
  Result := Default(TMQTTSubscriptionInfo);
end;

function TMQTTClient.GetSubInfo(TopicFilter: String): TMQTTSubscriptionInfo;
begin
  for Result in FSubInfos do
    if Result.TopicFilter = TopicFilter then
      exit;
  Result := Default(TMQTTSubscriptionInfo);;
end;

function TMQTTClient.HandleTopicAlias(ID: UInt16; Topic: String): String;
var
  I: Integer;
  A: TTopicAlias;
begin
  Result := Topic;
  if ID > 0 then
    if Topic <> '' then begin // both are set
      // either find existing and update it...
      for I := 0 to Length(FTopicAliases) do begin
        if FTopicAliases[I].ID = ID then begin
          FTopicAliases[I].Topic := Topic;
          exit(Topic);
        end
      end;
      // ...or add a new alias to the list
      A.ID := ID;
      A.Topic := Topic;
      FTopicAliases += [A];
    end
    else // only ID is set: look up topic name
      for A in FTopicAliases do
        if A.ID = ID then
          exit(A.Topic);
end;

constructor TMQTTClient.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FMaxQos := 2;
  FLock := TCriticalSection.Create;
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
  FLock.Acquire;
  FSubInfos := [];
  FRXQueue := [];
  FOnDisconnect := nil;
  FLock.Release;
  FListenThread.Terminate;
  FListenWake.SetEvent;
  if Connected then
    Disconect;
  FListenThread.WaitFor;
  FreeAndNil(FLock);
  FreeAndNil(FListenWake);
  inherited Destroy;
end;

function TMQTTClient.Connect(Host: String; Port: Word; ID, User, Pass: String): TMQTTError;
begin
  Result := ConnectSocket(Host, Port);
  if Result = mqeNoError then begin
    FKeepalive := MQTTDefaultKeepalive;
    FSocket.WriteMQTTConnect(ID, User, Pass, FKeepalive);
    FLastPing := Now;
  end;
end;

function TMQTTClient.Disconect: TMQTTError;
begin
  if not Connected then
    exit(mqeNotConnected);

  FClosing := True;
  fpshutdown(FSocket.Handle, SHUT_RDWR);
  FreeAndNil(FSocket);
  FLock.Acquire;
  FRXQueue := [];
  FSubInfos := [];
  FTopicAliases := [];
  FLock.Release;
  PushOnDisconnect;
  Result := mqeNoError;
end;

function TMQTTClient.Subscribe(ATopicFilter: String; AHandler: TMQTTRXFunc): TMQTTError;
var
  Found: Boolean = False;
  Info: TMQTTSubscriptionInfo;
  SubsID: UInt64;
begin
  if not Assigned(AHandler) then
    exit(mqeMissingHandler);
  if ATopicFilter = '' then
    exit(mqeEmptyTopic);
  if not Connected then
    exit(mqeNotConnected);

  Result := mqeNoError;
  FLock.Acquire;
  for Info in FSubInfos do begin
    if ATopicFilter = Info.TopicFilter then begin
      Found := True;
      break;
    end;
  end;
  FLock.Release;
  if Found then
    exit(mqeAlreadyConnected);

  SubsID := GetNewSubsID;
  FSocket.WriteMQTTSubscribe(ATopicFilter, GetNewPacketID, SubsID);

  Info.TopicFilter := ATopicFilter;
  Info.SubID := SubsID;
  Info.Handler := AHandler;
  FLock.Acquire;
  FSubInfos += [Info];
  FLock.Release;
end;

function TMQTTClient.Unsubscribe(ATopicFilter: String): TMQTTError;
var
  Found: Boolean = False;
  Info: TMQTTSubscriptionInfo;
  I: Integer = 0;
begin
  Result := mqeNoError;
  FLock.Acquire;
  for Info in FSubInfos do begin
    if ATopicFilter = Info.TopicFilter then begin
      Found := True;
      break;
    end;
    Inc(I);
  end;
  if not Found then begin
    FLock.Release;
    exit(mqeNotSubscribed);
  end;

  Delete(FSubInfos, I, 1);
  FLock.Release;

  FSocket.WriteMQTTUnsubscribe(ATopicFilter, GetNewPacketID);
end;

function TMQTTClient.Publish(Topic, Message, ResponseTopic: String; CorrelData: TBytes; QoS: Byte; Retain: Boolean): TMQTTError;
begin
  if not Connected then
    exit(mqeNotConnected);

  if QoS > FMaxQos then  // set by the server in CONNACK
    exit(mqeInvalidQoS);

  if Retain and not FRetainAvail then // set by server in CONNACK
    exit(mqeRetainUnavail);

  if QoS > 0 then
    exit(mqeNotYetImplemented); // fixme

  Result := mqeNoError;
  FSocket.WriteMQTTPublish(Topic, Message, ResponseTopic, CorrelData, GetNewPacketID, QoS, Retain);
end;

function TMQTTClient.Connected: Boolean;
begin
  Result := Assigned(FSocket) and not FClosing;
end;


end.

