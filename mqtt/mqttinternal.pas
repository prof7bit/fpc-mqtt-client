unit mqttinternal;

{$mode ObjFPC}{$H+}
{$ModeSwitch arrayoperators}

interface

uses
  Classes, SysUtils;

type
  EMQTTMalformedInteger = class(Exception);

  TMQTTPacketType = (
    // Ch. 2.1.2
    mqptReserved    = 0,
    mqptConnect     = 1,
    mqptConnAck     = 2,
    mqptPublish     = 3,
    mqptPubAck      = 4,
    mqptPubRec      = 5,
    mqptPubRel      = 6,
    mqptPubComp     = 7,
    mqptSubscribe   = 8,
    mqptSubAck      = 9,
    mqptUnsubscribe = 10,
    mqptUnsubAck    = 11,
    mqptPingReq     = 12,
    mqptPingResp    = 13,
    mqptDisconnect  = 14,
    mqptAuth        = 15
  );

  TStringPair = record
    Key: UTF8String;
    Value: UTF8String;
  end;

  { TMQTTParsedPacket }

  TMQTTParsedPacket = class
    PacketType: TMQTTPacketType;
    PacketFlags: Byte;
    Remaining: TMemoryStream;
    constructor Create(AType: TMQTTPacketType; AFlags: Byte; ARemaining: TMemoryStream);
    destructor Destroy; override;
    procedure Parse; virtual;
    function DebugPrint(FromStart: Boolean): String;
  end;


  { TMQTTConnAck }

  TMQTTConnAck = class(TMQTTParsedPacket) // Ch. 3.2
    ConnAckFlags: Byte;
    ReasonCode: Byte;
    ExpiryInterval: UInt32;
    RecvMax: UInt16;
    MaxQoS: Byte;
    RetainAvail: Boolean;
    MaxPackSize: UInt32;
    ClientID: UTF8String;
    TopicAliasMax: Byte;
    ReasonString: UTF8String;
    UserProperty: array of TStringPair;
    WildSubsAvail: Boolean;
    SubsIdentAvail: Boolean;
    SharedSubsAvail: Boolean;
    ServerKeepalive: UInt16;
    ResponseInfo: UTF8String;
    ServerRef: UTF8String;
    AuthMeth: UTF8String;
    AuthData: TBytes;
    procedure Parse; override;
  end;

  TMQTTPingResp = class(TMQTTParsedPacket) // Ch. 3.13
    // contains no data
  end;

  { TMQTTStream }

  TMQTTStream = class helper for TStream
    procedure WriteVarInt(X: UInt32);
    procedure WriteInt16Big(X: UInt16);
    procedure WriteInt32Big(X: UInt32);
    procedure WriteMQTTString(X: UTF8String);
    procedure WriteMQTTBin(X: TBytes);
    procedure WriteMQTTPacket(Typ: TMQTTPacketType; Flags: Byte; Remaining: TMemoryStream);
    procedure WriteMQTTConnect(ID, User, Pass: string; Keepalive: UInt16);
    procedure WriteMQTTPingReq;

    function ReadVarInt: UInt32;
    function ReadInt16Big: UInt16;
    function ReadInt32Big: UInt32;
    function ReadMQTTString: UTF8String;
    function ReadMQTTBin: TBytes;
    function ReadMQTTPacket: TMQTTParsedPacket;
  end;


implementation

{ TMQTTConnAck }

procedure TMQTTConnAck.Parse;
var
  PropEnd: UInt32;
  Prop: Byte;
  SP: TStringPair;
begin
  // Ch. 3.2
  with Remaining do begin
    ConnAckFlags := ReadByte;                      // Ch. 3.2.2.1
    ReasonCode := ReadByte;                        // Ch. 3.2.2.2
    // begin properties
    PropEnd := Position + ReadVarInt;              // Ch. 3.2.2.3.1
    // defaults
    RecvMax := $ffff;
    MaxQoS := 2;
    RetainAvail := True;
    MaxPackSize := High(MaxPackSize);
    WildSubsAvail := True;
    SubsIdentAvail := True;
    SharedSubsAvail := True;
    ServerKeepalive := High(ServerKeepalive);
    while Remaining.Position < PropEnd do begin
      Prop := ReadByte;
      case Prop of
        17: ExpiryInterval := ReadInt32Big;        // Ch. 3.2.2.3.2
        33: RecvMax := ReadInt16Big;               // Ch. 3.2.2.3.3
        36: MaxQoS := ReadByte;                    // Ch. 3.2.2.3.4
        37: RetainAvail := Boolean(ReadByte);      // Ch. 3.2.2.3.5
        39: MaxPackSize := ReadInt32Big;           // Ch. 3.2.2.3.6
        18: ClientID := ReadMQTTString;            // Ch. 3.2.2.3.7
        34: TopicAliasMax := ReadInt16Big;         // Ch. 3.2.2.3.8
        31: ReasonString := ReadMQTTString;        // Ch. 3.2.2.3.9
        38: begin                                  // Ch. 3.2.2.3.10
          SP.Key := ReadMQTTString;
          SP.Value := ReadMQTTString;
          UserProperty := UserProperty + [SP];
        end;
        40: WildSubsAvail := Boolean(ReadByte);    // Ch. 3.2.2.3.11
        41: SubsIdentAvail := Boolean(ReadByte);   // Ch. 3.2.2.3.12
        42: SharedSubsAvail :=  Boolean(ReadByte); // Ch. 3.2.2.3.13
        19: ServerKeepalive := ReadInt16Big;       // Ch. 3.2.2.3.14
        26: ResponseInfo := ReadMQTTString;        // Ch. 3.2.2.3.15
        28: ServerRef := ReadMQTTString;           // Ch. 3.2.2.3.16
        21: AuthMeth := ReadMQTTString;            // Ch. 3.2.2.3.17
        22: AuthData := ReadMQTTBin;               // Ch. 3.2.2.3.18
      end;
    end;
    // end properties
    // no payload
  end;
end;

{ TMQTTParsedPacket }

constructor TMQTTParsedPacket.Create(AType: TMQTTPacketType; AFlags: Byte; ARemaining: TMemoryStream);
begin
  inherited Create;
  Remaining := ARemaining;
  Remaining.Seek(0, soBeginning);
  PacketType := AType;
  PacketFlags := AFlags;
end;

destructor TMQTTParsedPacket.Destroy;
begin
  Remaining.Free;
  inherited Destroy;
end;

procedure TMQTTParsedPacket.Parse;
begin
  // empty default implementation, do nothing.
end;

function TMQTTParsedPacket.DebugPrint(FromStart: Boolean): String;
begin
  Result := '';
  if FromStart then
     Remaining.Seek(0, soBeginning);
  while Remaining.Position < Remaining.Size do begin
    Result += IntToHex(Remaining.ReadByte, 2) + ' ';
  end;
  Remaining.Seek(0, soBeginning);
end;

procedure TMQTTStream.WriteVarInt(X: UInt32);
var
  EncodedByte: Byte;
begin
  // Ch. 1.5.5
  repeat
    EncodedByte := X and $7f;
    X := X shr 7;
    if X > 0 then
       EncodedByte := EncodedByte or $80;
    Self.WriteByte(EncodedByte);
  until X = 0;
end;

procedure TMQTTStream.WriteInt16Big(X: UInt16);
begin
  // Ch. 1.5.2
  Self.WriteByte(X shr 8);
  Self.WriteByte(X);
end;

procedure TMQTTStream.WriteInt32Big(X: UInt32);
begin
  // Ch. 1.5.3
  Self.WriteByte(X shr 24);
  Self.WriteByte(X shr 16);
  Self.WriteByte(X shr 8);
  Self.WriteByte(X);
end;


procedure TMQTTStream.WriteMQTTString(X: UTF8String);
var
  L: UInt16;
begin
  // Ch. 1.5.4
  L := Length(X);
  Self.WriteInt16Big(L);
  Self.WriteBuffer(X[1], L); // traditionally strings have 1-based indices in Pascal
end;

procedure TMQTTStream.WriteMQTTBin(X: TBytes);
var
  L: UInt16;
begin
  // Ch. 1.5.6
  L := Length(X);
  Self.WriteInt16Big(L);
  Self.WriteBuffer(X[0], L);
end;

procedure TMQTTStream.WriteMQTTPacket(Typ: TMQTTPacketType; Flags: Byte; Remaining: TMemoryStream);
begin
  // each packet has a fixed header                  (Ch. 2.1.1)
  Self.WriteByte((ord(Typ) shl 4) or Flags);

  // folowed by a variable header,                   (Ch. 2.2)
  // and optionally a payload                        (Ch. 2.3)

  if Assigned(Remaining) then begin
    // The second element of the fixed header is a variable int
    // length field which counts the number of all remaining bytes
    // until the end of the packet.
    self.WriteVarInt(Remaining.Size);  // byte 2..     (Ch. 2.1.4)

    // Everything after that variable int field until the end has
    // already been prepared in the 'Remaining' memory stream object
    // and we append it here. After this the packet will be complete.
    Remaining.Seek(0, soBeginning);
    Self.CopyFrom(Remaining, Remaining.Size);
  end
  else
    self.WriteVarInt(0); // a packet without data, remaining length = 0
end;

procedure TMQTTStream.WriteMQTTConnect(ID, User, Pass: string; Keepalive: UInt16);
var
  Remaining: TMemoryStream;
begin
  // Ch. 3.1
  Remaining := TMemoryStream.Create;
  Remaining.WriteMQTTString('MQTT');      // byte 1..6   (Ch. 3.1.2.1)
  Remaining.WriteByte(5);                 // byte 7      (Ch. 3.1.2.2)
  Remaining.WriteByte(%11000010);         // byte 8      (Ch. 3.1.2.3)
  Remaining.WriteInt16Big(Keepalive);     // byte 9..10  (Ch. 3.1.2.10)

  // begin properties                                    (Ch. 3.1.2.11)
  Remaining.WriteVarInt(0);               // length      (Ch. 3.1.2.11.1)
  // empty
  // end properties

  // begin payload                                       (Ch. 3.1.3)
  Remaining.WriteMQTTString(ID);          // client id   (Ch. 3.1.3.1)
  // no will properties                                  (Ch. 3.1.3.2)
  // no will topic                                       (Ch. 3.1.3.3)
  // no will payload                                     (Ch. 3.1.3.4)
  Remaining.WriteMQTTString(User);        // username    (Ch. 3.1.3.5)
  Remaining.WriteMQTTString(Pass);        // password    (Ch. 3.1.3.6)
  // end payload

  // write an MQTT packet with fixed header and remaining data
  Self.WriteMQTTPacket(mqptConnect, 0, Remaining);
  Remaining.Free;
end;

procedure TMQTTStream.WriteMQTTPingReq;
begin
  // Ch. 3.12
  Self.WriteMQTTPacket(mqptPingReq, 0, nil);
end;


function TMQTTStream.ReadVarInt: UInt32;
var
  Multiplier: UInt32;
  EncodedByte: Byte;
  Count: Byte;
begin
  // Ch. 1.5.5
  Multiplier := 1;
  Result := 0;
  Count := 0;
  repeat
    if Count > 3 then
       raise EMQTTMalformedInteger.Create('malformed encoded integer');
    EncodedByte := Self.ReadByte;
    Result += (EncodedByte and $7f) * Multiplier;
    Multiplier *= 128;
    Inc(Count);
  until (EncodedByte and $80) = 0;
end;

function TMQTTStream.ReadInt16Big: UInt16;
begin
  // Ch. 1.5.2
  Result := Self.ReadByte shl 8;
  Result += Self.ReadByte;
end;

function TMQTTStream.ReadInt32Big: UInt32;
begin
  // Ch. 1.5.3
  Result := Self.ReadByte shl 24;
  Result += Self.ReadByte shl 16;
  Result += Self.ReadByte shl 8;
  Result += Self.ReadByte;
end;

function TMQTTStream.ReadMQTTString: UTF8String;
var
  L: UInt16;
begin
  // Ch. 1.5.4
  L := Self.ReadInt16Big;
  SetLength(Result, L);
  Self.ReadBuffer(Result[1], L); // traditionally strings have 1-based indices in Pascal
end;

function TMQTTStream.ReadMQTTBin: TBytes;
var
  L: UInt16;
begin
  // Ch. 1.5.6
  Result := [];
  L := Self.ReadInt16Big;
  SetLength(Result, L);
  Self.ReadBuffer(Result[0], L);
end;

function TMQTTStream.ReadMQTTPacket: TMQTTParsedPacket;
var
  Fixed: Byte;
  Typ: TMQTTPacketType;
  Flags: Byte;
  RemLen: UInt32;
  Remaining: TMemoryStream;
begin
  // fixed header
  Fixed := Self.ReadByte;
  Typ := TMQTTPacketType(Fixed shr 4);
  Flags := Fixed and $0f;

  // variable header and all remaining bytes
  RemLen := Self.ReadVarInt;
  Remaining := TMemoryStream.Create;
  if RemLen > 0 then
    Remaining.CopyFrom(Self, RemLen);
  case Typ of
    mqptConnAck: Result := TMQTTConnAck.Create(Typ, Flags, Remaining);
    mqptPingResp: Result := TMQTTPingResp.Create(Typ, Flags, Remaining);
  else
    Result := TMQTTParsedPacket.Create(Typ, Flags, Remaining);
  end;
  Result.Parse;
end;

{ TMQTTStream }

end.

