unit mqtt;

{$mode ObjFPC}{$H+}
{$ModeSwitch arrayoperators}

interface

uses
  Classes, sysutils, Sockets, SSockets, syncobjs, mqttinternal, fptimer;

const
  MQTTDefaultKeepalive: UInt16 = 120; // seconds

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
    mqeNotSubscribed = 8
  );

  TMQTTClient = class;
  TMQTTDebugFunc = procedure(Txt: String) of object;
  TMQTTDisconnectFunc = procedure(AClient: TMQTTClient) of object;
  TMQTTRXFunc = procedure(AClient: TMQTTClient; ATopic, AMessage: String) of object;

  TMQTTSubscriptionInfo = record
    Topic: String;
    Handler: TMQTTRXFunc;
  end;

  TMQTTRXData = record
    Topic: String;
    Message: String;
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
    FOnDisconnect: TMQTTDisconnectFunc;
    FSubscriptions: array of TMQTTSubscriptionInfo;
    FRXQueue: array of TMQTTRXData;
    FDebugTxt: String;
    FLock: TCriticalSection;
    FKeepalive: UInt16;
    FLastPing: TDateTime;
    FKeepaliveTimer: TFPTimer;
    procedure DebugSync;
    procedure Debug(Txt: String);
    procedure Debug(Txt: String; Args: array of const);
    procedure PushOnDisconnect;
    procedure PopOnDisconnect;
    procedure PushOnRX(ATopic, AMessage: String);
    procedure popOnRX;
    procedure OnTimer(Sender: TObject);
    function ConnectSocket(Host: String; Port: Word): TMQTTError;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function Connect(Host: String; Port: Word; ID, User, Pass: String): TMQTTError;
    function Disconect: TMQTTError;
    function Subscribe(ATopic: String; AHandler: TMQTTRXFunc): TMQTTError;
    function Unsubscribe(ATopic: String): TMQTTError;
    function Publish(ATopic, AMessage: String): TMQTTError;
    function Connected: Boolean;
    property OnDebug: TMQTTDebugFunc read FOnDebug write FOnDebug;
    property OnDisconnect: TMQTTDisconnectFunc read FOnDisconnect write FOnDisconnect;
  end;

implementation

function Min(A, B: UInt16): UInt16;
begin
  if A < B then
    Result := A
  else
    Result := B;
end;

{ TMQTTLIstenThread }

procedure TMQTTLIstenThread.Execute;
var
  P: TMQTTParsedPacket;
  CA: TMQTTConnAck;
begin
  repeat
    if Client.Connected then begin
      try
        P := Client.FSocket.ReadMQTTPacket;
        // Client.Debug('RX: %s %s', [P.ClassName, P.DebugPrint(True)]);
        if P is TMQTTConnAck then begin
          CA := TMQTTConnAck(P);
          Client.FKeepalive := Min(Client.FKeepalive, CA.ServerKeepalive);
          Client.Debug('keepalive is %d seconds', [Client.FKeepalive]);
          Client.Debug('connected.');
        end
        else begin
          Client.Debug('RX: unknown packet type %d flags %d', [P.PacketType, P.PacketFlags]);
          Client.Debug('RX: data %s', [P.ClassName, P.DebugPrint(True)]);
        end;
      except
        Client.Disconect;
      end;
    end
    else
      Sleep(100);
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
  FDebugTxt := Txt;
  TThread.Synchronize(nil, @DebugSync);
end;

procedure TMQTTClient.Debug(Txt: String; Args: array of const);
begin
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

procedure TMQTTClient.PushOnRX(ATopic, AMessage: String);
var
  Data: TMQTTRXData;
  Info: TMQTTSubscriptionInfo;
  Found: Boolean = False;
begin
  FLock.Acquire;
  for Info in FSubscriptions do begin
    if Info.Topic = ATopic then begin
       Found := True;
       break;
    end;
  end;
  if not found then
    FLock.Release
  else begin
    Data.Topic := ATopic;
    Data.Message := AMessage;
    Data.Handler := Info.Handler;
    FRXQueue := [Data] + FRXQueue;
    FLock.Release;
    TThread.Queue(nil, @popOnRX);
  end;
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
      Data.Handler(Self, Data.Topic, Data.Message);
  end;
end;

procedure TMQTTClient.OnTimer(Sender: TObject);
begin
  if Connected then begin
    if Now - FLastPing > FKeepalive / (60 * 60 * 24) then begin
      Debug('ping');
      FSocket.WriteMQTTPingReq;
      FLastPing := Now;
    end;
  end;
end;

function TMQTTClient.ConnectSocket(Host: String; Port: Word): TMQTTError;
var
  Data: TMemoryStream;
begin
  if Connected then
    Result := mqeAlreadyConnected
  else begin
    FClosing := False;
    try
      FSocket := TInetSocket.Create(Host, Port);
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

constructor TMQTTClient.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FLock := TCriticalSection.Create;
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
  FSubscriptions := [];
  FRXQueue := [];
  FOnDisconnect := nil;
  FLock.Release;
  FListenThread.Terminate;
  if Connected then
    Disconect;
  FreeAndNil(FLock);
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
  FSubscriptions := [];
  FLock.Release;
  PushOnDisconnect;
  Result := mqeNoError;
end;

function TMQTTClient.Subscribe(ATopic: String; AHandler: TMQTTRXFunc): TMQTTError;
var
  Found: Boolean = False;
  Info: TMQTTSubscriptionInfo;
begin
  if not Assigned(AHandler) then
    exit(mqeMissingHandler);
  if ATopic = '' then
    exit(mqeEmptyTopic);
  if not Connected then
    exit(mqeNotConnected);

  Result := mqeNoError;
  FLock.Acquire;
  for Info in FSubscriptions do begin
    if ATopic = Info.Topic then begin
      Found := True;
      break;
    end;
  end;
  FLock.Release;
  if Found then
    exit(mqeAlreadyConnected);

  // todo: implement subscribe

  Info.Topic := ATopic;
  Info.Handler := AHandler;
  FLock.Acquire;
  FSubscriptions := FSubscriptions + [Info];
  FLock.Release;
end;

function TMQTTClient.Unsubscribe(ATopic: String): TMQTTError;
var
  Found: Boolean = False;
  Info: TMQTTSubscriptionInfo;
  I: Integer = 0;
begin
  Result := mqeNoError;
  FLock.Acquire;
  for Info in FSubscriptions do begin
    if ATopic = Info.Topic then begin
      Found := True;
      break;
    end;
    Inc(I);
  end;
  if not Found then begin
    FLock.Release;
    exit(mqeNotSubscribed);
  end;

  Delete(FSubscriptions, I, 1);
  FLock.Release;

  // todo: implement unsubscribe
end;

function TMQTTClient.Publish(ATopic, AMessage: String): TMQTTError;
begin
  if not Connected then
    exit(mqeNotConnected);

  Result := mqeNoError;
  // todo: implement publish
end;

function TMQTTClient.Connected: Boolean;
begin
  Result := Assigned(FSocket) and not FClosing;
end;


end.

