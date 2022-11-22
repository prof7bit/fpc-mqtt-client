{ MQTT client internal data structures and procedures

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
unit mqttinternal;

{$mode ObjFPC}{$H+}
{$ModeSwitch arrayoperators}
{$PackEnum 1}
{$PackSet 1}

interface

uses
  Classes, SysUtils;

type
  EMQTTProtocolError = class(Exception);
  EMQTTMalformedInteger = class(EMQTTProtocolError);
  EMQTTUnexpectedProperty = class(EMQTTProtocolError);

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

  TMQTTStringPair = record
    Key: UTF8String;
    Val: UTF8String;
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

  TMQTTConnAck = class(TMQTTParsedPacket)     // Ch. 3.2
    ConnAckFlags: Byte;
    ReasonCode: Byte;
    SessionExpiry: UInt32;
    RecvMax: UInt16;
    MaxQoS: Byte;
    RetainAvail: Boolean;
    MaxPackSize: UInt32;
    ClientID: UTF8String;
    TopicAliasMax: Byte;
    ReasonString: UTF8String;
    UserProperty: array of TMQTTStringPair;
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

  { TMQTTPublish }

  TMQTTPublish = class(TMQTTParsedPacket)     // Ch. 3.3
    Dup: Boolean;
    QoS: Byte;
    Retain: Boolean;
    TopicName: UTF8String;
    PacketID: UInt16;
    PayloadFormat: Byte;
    ExpiryInterval: UInt32;
    TopicAlias: UInt16;
    RespTopic: UTF8String;
    CorrelData: TBytes;
    UserProperty: array of TMQTTStringPair;
    SubscriptionID: array of UInt32;
    ContentType: UTF8String;
    Message: String;
    procedure Parse; override;
  end;

  { TMQTTPubAck }

  TMQTTPubAck = class(TMQTTParsedPacket)      // Ch. 3.4
    PacketID: Uint16;
    ReasonCode: Byte;
    ReasonString: UTF8String;
    UserProperty: array of TMQTTStringPair;
    procedure Parse; override;
  end;

  TMQTTPubRec = class(TMQTTPubAck)            // Ch. 3.5
    // exact same structure as PubAck
  end;

  TMQTTPubRel = class(TMQTTPubAck)            // Ch. 3.6
    // exact same structure as PubAck
  end;

  TMQTTPubComp = class(TMQTTPubAck)           // Ch. 3.7
    // exact same structure as PubAck
  end;

  { TMQTTSubAck }

  TMQTTSubAck = class(TMQTTParsedPacket)      // Ch. 3.9
    PacketID: UInt16;
    ReasonString: UTF8String;
    UserProperty: array of TMQTTStringPair;
    ReasonCodes: array of Byte;
    procedure Parse; override;
  end;

  { TMQTTUnsubAck }

  TMQTTUnsubAck = class(TMQTTSubAck)          // Ch. 3.11
    // exact same structure as SubAck
  end;

  TMQTTPingResp = class(TMQTTParsedPacket)    // Ch. 3.13
    // contains no data
  end;

  { TMQTTDisconnect }

  TMQTTDisconnect = class(TMQTTParsedPacket)  // Ch. 3.14
    ReasonCode: Byte;
    ExpiryInterval: UInt32;
    ReasonString: UTF8String;
    UserProperty: array of TMQTTStringPair;
    ServerReference: UTF8String;
    procedure Parse; override;
  end;

  CMQTTParsedPacket = class of TMQTTParsedPacket;

  { TMQTTStream }

  TMQTTStream = class helper for TStream
    procedure WriteVarInt(X: UInt32);
    procedure WriteInt16Big(X: UInt16);
    procedure WriteInt32Big(X: UInt32);
    procedure WriteMQTTString(X: UTF8String);
    procedure WriteMQTTBin(X: TBytes);
    procedure WriteMQTTPacket(Typ: TMQTTPacketType; Flags: Byte; Remaining: TMemoryStream);
    procedure WriteMQTTConnect(ID, User, Pass: string; Keepalive: UInt16; CleanStart: Boolean; SessionExpiry: UInt32);
    procedure WriteMQTTPingReq;
    procedure WriteMQTTSubscribe(Topic: String; PacketID: UInt16; SubsID: UInt32);
    procedure WriteMQTTPublish(Topic, Message, ResponseTopic: String; CorrelData: TBytes; PacketID: UInt16; QoS: Byte; Retain: Boolean; Dup: Boolean);
    procedure WriteMQTTUnsubscribe(Topic: String; PacketID: UInt16);
    procedure WriteMQTTPubAck(PacketID: UInt16; ReasonCode: Byte);
    procedure WriteMQTTPubRel(PacketID: UInt16; ReasonCode: Byte);

    function ReadVarInt: UInt32;
    function ReadInt16Big: UInt16;
    function ReadInt32Big: UInt32;
    function ReadMQTTString: UTF8String;
    function ReadMQTTBin: TBytes;
    function ReadMQTTStringPair: TMQTTStringPair;
    function ReadMQTTPacket: TMQTTParsedPacket;
    function CopyTo(Dest: TStream; Size: Int64): Int64;
  end;

implementation
const
  PacketClasses: array[TMQTTPacketType] of CMQTTParsedPacket = (
    TMQTTParsedPacket,  // reserved
    TMQTTParsedPacket,  // connect (we don't receive these)
    TMQTTConnAck,
    TMQTTPublish,
    TMQTTPubAck,
    TMQTTPubRec,
    TMQTTPubRel,
    TMQTTPubComp,
    TMQTTParsedPacket,  // subscribe (we don't revceive these)
    TMQTTSubAck,
    TMQTTParsedPacket,  // unsubscribe (we don't revceive these)
    TMQTTUnsubAck,
    TMQTTParsedPacket,  // pingreq (we don't revceive these)
    TMQTTPingResp,
    TMQTTDisconnect,
    TMQTTParsedPacket   // auth (fixme, need to implement this)
  );

{ TMQTTParsedPacket }

constructor TMQTTParsedPacket.Create(AType: TMQTTPacketType; AFlags: Byte; ARemaining: TMemoryStream);
begin
  inherited Create;
  Remaining := ARemaining;
  Remaining.Seek(0, soBeginning);
  PacketType := AType;
  PacketFlags := AFlags;
  Parse;
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

{ TMQTTConnAck }

procedure TMQTTConnAck.Parse;
var
  PropLen: UInt32;
  PropEnd: UInt32;
  Prop: Byte;
begin
  // Ch. 3.2
  with Remaining do begin
    ConnAckFlags := ReadByte;                       // Ch. 3.2.2.1
    ReasonCode := ReadByte;                         // Ch. 3.2.2.2
    // begin properties
    PropLen := ReadVarInt;                          // Ch. 3.2.2.3.1
    PropEnd := Position + PropLen;
    // defaults
    RecvMax := $ffff;
    MaxQoS := 2;
    RetainAvail := True;
    MaxPackSize := High(MaxPackSize);
    WildSubsAvail := True;
    SubsIdentAvail := True;
    SharedSubsAvail := True;
    ServerKeepalive := High(ServerKeepalive);
    while Position < PropEnd do begin
      Prop := ReadByte;
      case Prop of
        17: SessionExpiry := ReadInt32Big;          // Ch. 3.2.2.3.2
        33: RecvMax := ReadInt16Big;                // Ch. 3.2.2.3.3
        36: MaxQoS := ReadByte;                     // Ch. 3.2.2.3.4
        37: RetainAvail := Boolean(ReadByte);       // Ch. 3.2.2.3.5
        39: MaxPackSize := ReadInt32Big;            // Ch. 3.2.2.3.6
        18: ClientID := ReadMQTTString;             // Ch. 3.2.2.3.7
        34: TopicAliasMax := ReadInt16Big;          // Ch. 3.2.2.3.8
        31: ReasonString := ReadMQTTString;         // Ch. 3.2.2.3.9
        38: UserProperty += [ReadMQTTStringPair];   // Ch. 3.2.2.3.10
        40: WildSubsAvail := Boolean(ReadByte);     // Ch. 3.2.2.3.11
        41: SubsIdentAvail := Boolean(ReadByte);    // Ch. 3.2.2.3.12
        42: SharedSubsAvail :=  Boolean(ReadByte);  // Ch. 3.2.2.3.13
        19: ServerKeepalive := ReadInt16Big;        // Ch. 3.2.2.3.14
        26: ResponseInfo := ReadMQTTString;         // Ch. 3.2.2.3.15
        28: ServerRef := ReadMQTTString;            // Ch. 3.2.2.3.16
        21: AuthMeth := ReadMQTTString;             // Ch. 3.2.2.3.17
        22: AuthData := ReadMQTTBin;                // Ch. 3.2.2.3.18
      else
        raise EMQTTUnexpectedProperty.Create(Format('unexpected prop %d in CONNACK packet', [Prop]));
      end;
    end;
    // end properties
    // no payload
  end;
end;

{ TMQTTPublish }

procedure TMQTTPublish.Parse;
var
  PropLen: UInt32;
  PropEnd: UInt32;
  Prop: Byte;
begin
  Retain := Boolean(PacketFlags and %0001);
  QoS := (PacketFlags and %0110) shr 1;
  Dup := Boolean(PacketFlags and %1000);
  with Remaining do begin
    TopicName := ReadMQTTString;                  // Ch. 3.3.2.1
    if QoS > 0 then
      PacketID := ReadInt16Big;                   // Ch. 3.3.2.2

    // begin properties
    PropLen := ReadVarInt;                        // Ch. 3.3.2.3.1
    PropEnd := Position + PropLen;
    while Position < PropEnd do begin
      Prop := ReadByte;
      case Prop of
        01: PayloadFormat := ReadByte;            // Ch. 3.3.2.3.2
        02: ExpiryInterval := ReadInt32Big;       // Ch. 3.3.2.3.3
        35: TopicAlias := ReadInt16Big;           // Ch. 3.3.2.3.4
        08: RespTopic := ReadMQTTString;          // Ch. 3.3.2.3.5
        09: CorrelData := ReadMQTTBin;            // Ch. 3.3.2.3.6
        38: UserProperty += [ReadMQTTStringPair]; // Ch. 3.3.2.3.7
        11: SubscriptionID += [ReadVarInt];       // Ch. 3.3.2.3.8
        03: ContentType := ReadMQTTString;        // Ch. 3.3.2.3.9
      else
        raise EMQTTUnexpectedProperty.Create(Format('unexpected prop %d in PUBLISH packet', [Prop]));
      end;
    end;
    // end properties

    // begin payload
    SetLength(Message, Size - Position);
    ReadBuffer(Message[1], Size - Position);
    // end payload
  end;
end;

{ TMQTTPubAck }

procedure TMQTTPubAck.Parse;
var
  PropLen: UInt32;
  PropEnd: UInt32;
  Prop: Byte;
begin
  with Remaining do begin
    PacketID := ReadInt16Big;                       // Ch. 3.4.2

    // Attention! Chapter 3.4.2.1 states that if remaining length = 2
    // then there will be no reason code amd 0 is assumed instead.
    // Consequently there also won't be a property section and not
    // even a property length, because all bytes are already consumed.
    if Remaining.Size = 2 then
      ReasonCode := 0

    else begin
      ReasonCode := ReadByte;                       // Ch. 3.4.2.1

      // Again, according to Chapter 3.4.2.2.1 another special condition:
      // if remaining legnth is less than 4 there won't be a property
      // length field and 0 is assumed.
      if Remaining.Size < 4 then
        PropLen := 0
      else
        PropLen := ReadVarInt;                      // Ch. 3.4.2.2.1

      // begin properties                           // Ch. 3.4.2.2
      PropEnd := Position + PropLen;
      while Position < PropEnd do begin
        Prop := ReadByte;
        case Prop of
          31: ReasonString := ReadMQTTString;       // Ch. 3.4.2.2.2
          38: UserProperty += [ReadMQTTStringPair]; // Ch. 3.4.2.2.3
        else
          raise EMQTTUnexpectedProperty.Create(Format('unexpected prop %d in PUBACK packet', [Prop]));
        end
      end;
      // end properties

    end;

    // no payload                                   // Ch. 3.4.3
  end;
end;

{ TMQTTSubAck }

procedure TMQTTSubAck.Parse;
var
  PropLen: UInt32;
  PropEnd: UInt32;
  Prop: Byte;
begin
  with Remaining do begin
    PacketID := ReadInt16Big;                     // Ch. 3.9.2

    // begin properties
    PropLen := ReadVarInt;                        // Ch. 3.9.2.1.1
    PropEnd := Position + PropLen;
    while Position < PropEnd do begin
      Prop := ReadByte;
      case Prop of
        31: ReasonString := ReadMQTTString;       // Ch. 3.9.2.1.2
        38: UserProperty += [ReadMQTTStringPair]; // Ch. 3.9.2.1.3
        else
          raise EMQTTUnexpectedProperty.Create(Format('unexpected prop %d in SUBACK packet', [Prop]));
      end;
    end;
    // end properties

    // begin payload                              // Ch. 3.9.3
    while Position < Size do begin
      ReasonCodes += [ReadByte];
    end;
    // end payload
  end;
end;

{ TMQTTDisconnect }

procedure TMQTTDisconnect.Parse;
var
  PropLen: UInt32;
  PropEnd: UInt32;
  Prop: Byte;
begin
  with Remaining do begin
    // Reason code is omitted and assumed zero if remaining length
    // is less than 1 (Ch. 3.14.2.1). At this point we stop parsing,
    // there is no data anymore.
    If Remaining.Size < 1 then begin
      ReasonCode := 0;
      exit;
    end
    else
      ReasonCode := ReadByte;                     // Ch. 3.14.2.1

    // begin properties

    // Property Lenth is omitted and assumed zero if remaining length
    // is less than 2 (Ch. 3.14.2.2.1). At this point we stop parsing,
    // there is no data anymore.
    if Remaining.Size < 2 then begin
      exit;
    end
    else
      PropLen := ReadVarInt;                      // Ch. 3.14.2.2.1

    PropEnd := Position + PropLen;
    while Position < PropEnd do begin
      Prop := ReadByte;
      case Prop of
        17: ExpiryInterval := ReadInt32Big;       // Ch. 3.14.2.2.2
        31: ReasonString := ReadMQTTString;       // Ch. 3.14.2.2.3
        38: UserProperty += [ReadMQTTStringPair]; // Ch. 3.14.2.2.4
        28: ServerReference := ReadMQTTString;    // Ch. 3.14.2.5
      else
        raise EMQTTUnexpectedProperty.Create(Format('unexpected prop %d in DISCONNECT packet', [Prop]));
      end
    end;
    // end properties

    // no payload
  end;
end;

{ TMQTTStream }

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
    WriteByte(EncodedByte);
  until X = 0;
end;

procedure TMQTTStream.WriteInt16Big(X: UInt16);
begin
  // Ch. 1.5.2
  WriteByte(X shr 8);
  WriteByte(X);
end;

procedure TMQTTStream.WriteInt32Big(X: UInt32);
begin
  // Ch. 1.5.3
  WriteByte(X shr 24);
  WriteByte(X shr 16);
  WriteByte(X shr 8);
  WriteByte(X);
end;

procedure TMQTTStream.WriteMQTTString(X: UTF8String);
var
  L: UInt16;
begin
  // Ch. 1.5.4
  L := Length(X);
  WriteInt16Big(L);
  WriteBuffer(X[1], L); // traditionally strings have 1-based indices in Pascal
end;

procedure TMQTTStream.WriteMQTTBin(X: TBytes);
var
  L: UInt16;
begin
  // Ch. 1.5.6
  L := Length(X);
  WriteInt16Big(L);
  WriteBuffer(X[0], L);
end;

procedure TMQTTStream.WriteMQTTPacket(Typ: TMQTTPacketType; Flags: Byte; Remaining: TMemoryStream);
begin
  // each packet has a fixed header                             (Ch. 2.1.1)
  WriteByte((ord(Typ) shl 4) or Flags);

  // folowed by a variable header,                              (Ch. 2.2)
  // and optionally a payload                                   (Ch. 2.3)

  if Assigned(Remaining) then begin
    // The second element of the fixed header is a variable int
    // length field which counts the number of all remaining bytes
    // until the end of the packet.
    WriteVarInt(Remaining.Size);  // byte 2..                   (Ch. 2.1.4)

    // Everything after that variable int field until the end has
    // already been prepared in the 'Remaining' memory stream object
    // and we append it here. After this the packet will be complete.
    Remaining.Seek(0, soBeginning);
    CopyFrom(Remaining, Remaining.Size);
  end
  else
    WriteVarInt(0); // a packet without data, remaining length = 0
end;

procedure TMQTTStream.WriteMQTTConnect(ID, User, Pass: string; Keepalive: UInt16; CleanStart: Boolean; SessionExpiry: UInt32);
type
  TConnectFlag = (          // Ch. 3.1.2.3
    cfReserved0   = 0,
    cfCleanStart  = 1,      // Ch. 3.1.2.4
    cfWill        = 2,      // Ch. 3.1.2.5
    cfWillQoS1    = 3,      // Ch. 3.1.2.6
    cfWillQoS2    = 4,      // Ch. 3.1.2.6
    cfWillRetain  = 5,      // Ch. 3.1.2.7
    cfPass        = 6,      // Ch. 3.1.2.9
    cfUser        = 7       // Ch. 3.1.2.8
  );

var
  Remaining: TMemoryStream;
  ConnectFlags: Set of TConnectFlag;
begin
  ConnectFlags := [cfUser, cfPass];
  if CleanStart then
    ConnectFlags += [cfCleanStart];

  // Ch. 3.1.2
  Remaining := TMemoryStream.Create;
  with Remaining do begin
    WriteMQTTString('MQTT');                  // byte 1..6        (Ch. 3.1.2.1)
    WriteByte(5);                             // version          (Ch. 3.1.2.2)
    WriteByte(Byte(ConnectFlags));            // connect flags    (Ch. 3.1.2.3)
    WriteInt16Big(Keepalive);                 // keepalive        (Ch. 3.1.2.10)

    // begin properties                                           (Ch. 3.1.2.11)
    with TMemoryStream.Create do begin
      if SessionExpiry > 0 then begin
        WriteByte(17);                        // Session Expiry   (Ch. 3.1.2.11.2)
        WriteInt32Big(SessionExpiry);
      end;
      WriteByte(34);                          // Topic Alias Max  (Ch. 3.1.2.11.5)
      WriteInt16Big($ffff);
      Seek(0, soBeginning);
      Remaining.WriteVarInt(Size);            // props length     (Ch. 3.1.2.11.1)
      CopyTo(Remaining, Size);                // props data
      Free;
    end;
    // end properties

    // begin payload                                              (Ch. 3.1.3)
    WriteMQTTString(ID);                      // client id        (Ch. 3.1.3.1)
    // no will properties                                         (Ch. 3.1.3.2)
    // no will topic                                              (Ch. 3.1.3.3)
    // no will payload                                            (Ch. 3.1.3.4)
    WriteMQTTString(User);                    // username         (Ch. 3.1.3.5)
    WriteMQTTString(Pass);                    // password         (Ch. 3.1.3.6)
    // end payload
  end;

  // write an MQTT packet with fixed header and remaining data
  WriteMQTTPacket(mqptConnect, 0, Remaining);
  Remaining.Free;
end;

procedure TMQTTStream.WriteMQTTPingReq;
begin
  // Ch. 3.12
  WriteMQTTPacket(mqptPingReq, 0, nil);
end;

procedure TMQTTStream.WriteMQTTSubscribe(Topic: String; PacketID: UInt16; SubsID: UInt32);
var
  Remaining: TMemoryStream;
  SubsOpt: Byte;
begin
  // Ch. 3.8
  Remaining := TMemoryStream.Create;
  with Remaining do begin
    WriteInt16Big(PacketID);                  // bytes 1..2       (Ch. 3.8.2)

    // begin props                            //                  (Ch. 3.8.2.1)
    with TMemoryStream.Create do begin
      if SubsID > 0 then begin
        WriteByte(11);                        // subcription ID   (Ch. 3.8.2.1.2)
        WriteVarInt(SubsID);
      end;
      Seek(0, soBeginning);
      Remaining.WriteVarInt(Size);
      CopyTo(Remaining, Size);
      Free;
    end;
    // end props

    // begin payload
    SubsOpt := %00000010;                     // max QoS = 2
    WriteMQTTString(Topic);                   //                  (Ch. 3.8.3)
    WriteByte(SubsOpt);                       // subscr. opt      (Ch. 3.8.3.1)
    // end payload
  end;

  // write an MQTT packet with fixed header and remaining data
  WriteMQTTPacket(mqptSubscribe, %0010, Remaining);
  Remaining.Free;
end;

procedure TMQTTStream.WriteMQTTPublish(Topic, Message, ResponseTopic: String; CorrelData: TBytes; PacketID: UInt16; QoS: Byte; Retain: Boolean; Dup: Boolean);
var
  Remaining: TMemoryStream;
  Flags: Byte = 0;
begin
  // Ch. 3.8

  Flags := Flags or ((QoS and %11) << 1);
  if Retain then
    Flags := Flags or 1;
  if Dup then
    Flags := Flags or (1 shl 3);

  Remaining := TMemoryStream.Create;
  with Remaining do begin
    WriteMQTTString(Topic);
    if QoS > 0 then
       WriteInt16Big(PacketID);

    // begin props
    with TMemoryStream.Create do begin
      if ResponseTopic <> '' then begin
        WriteByte(8);
        WriteMQTTString(ResponseTopic);       // response topic   (Ch. 3.3.2.3.5)
      end;
      if Length(CorrelData) > 0 then begin
        WriteByte(9);
        WriteMQTTBin(CorrelData);             // correlation data (Ch. 3.3.2.3.6)
      end;
      Seek(0, soBeginning);
      Remaining.WriteVarInt(Size);
      CopyTo(Remaining, Size);
      Free;
    end;
    // end props

    // begin payload
    WriteBuffer(Message[1], Length(Message)); //                  (Ch. 3.3.3)
    // end payload
  end;

  // write an MQTT packet with fixed header and remaining data
  WriteMQTTPacket(mqptPublish, Flags, Remaining);
  Remaining.Free;
end;

procedure TMQTTStream.WriteMQTTUnsubscribe(Topic: String; PacketID: UInt16);
var
  Remaining: TMemoryStream;
begin
  // Ch. 3.10
  Remaining := TMemoryStream.Create;
  with Remaining do begin
    WriteInt16Big(PacketID);        // Ch. 3.10.2


    // begin props                  // Ch. 3.10.2.1
    WriteVarInt(0);
    // no props
    // end props

    // begin payload
    WriteMQTTString(Topic);         // Ch. 3.10.3
    // end payload
  end;

  // write an MQTT packet with fixed header and remaining data
  WriteMQTTPacket(mqptUnsubscribe, %0010, Remaining);
  Remaining.Free;
end;

procedure TMQTTStream.WriteMQTTPubAck(PacketID: UInt16; ReasonCode: Byte);
var
  Remaining: TMemoryStream;
begin
  // Ch. 3.4
  Remaining := TMemoryStream.Create;
  with Remaining do begin
    WriteInt16Big(PacketID);        // Ch. 3.4.2
    WriteByte(ReasonCode);          // Ch, 3.4.2, 3.4.2.1
    WriteVarInt(0);                 // Ch. 3.4.2 (prop len)
    // no properties
    // no payload
  end;
  WriteMQTTPacket(mqptPubAck, %0000, Remaining);
  Remaining.Free;
end;

procedure TMQTTStream.WriteMQTTPubRel(PacketID: UInt16; ReasonCode: Byte);
var
  Remaining: TMemoryStream;
begin
  // Ch. 3.6
  Remaining := TMemoryStream.Create;
  with Remaining do begin
    WriteInt16Big(PacketID);        // Ch. 3.6.2
    WriteByte(ReasonCode);          // Ch. 3.6.2, 3.6.2.1
    WriteVarInt(0);                 // Ch. 3.6.2 (prop len)
    // no properties
    // no payload
  end;
  WriteMQTTPacket(mqptPubRel, %0010, Remaining);
  Remaining.Free;
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
    EncodedByte := ReadByte;
    Result += (EncodedByte and $7f) * Multiplier;
    Multiplier *= 128;
    Inc(Count);
  until (EncodedByte and $80) = 0;
end;

function TMQTTStream.ReadInt16Big: UInt16;
begin
  // Ch. 1.5.2
  Result := ReadByte shl 8;
  Result += ReadByte;
end;

function TMQTTStream.ReadInt32Big: UInt32;
begin
  // Ch. 1.5.3
  Result := ReadByte shl 24;
  Result += ReadByte shl 16;
  Result += ReadByte shl 8;
  Result += ReadByte;
end;

function TMQTTStream.ReadMQTTString: UTF8String;
var
  L: UInt16;
begin
  // Ch. 1.5.4
  Result := '';
  L := ReadInt16Big;
  SetLength(Result, L);
  ReadBuffer(Result[1], L); // traditionally strings have 1-based indices in Pascal
end;

function TMQTTStream.ReadMQTTBin: TBytes;
var
  L: UInt16;
begin
  // Ch. 1.5.6
  Result := [];
  L := ReadInt16Big;
  SetLength(Result, L);
  ReadBuffer(Result[0], L);
end;

function TMQTTStream.ReadMQTTStringPair: TMQTTStringPair;
begin
  Result.Key := ReadMQTTString;
  Result.Val := ReadMQTTString;
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
  Fixed := ReadByte;
  Typ := TMQTTPacketType(Fixed shr 4);
  Flags := Fixed and $0f;

  // variable header and all remaining bytes
  RemLen := ReadVarInt;
  Remaining := TMemoryStream.Create;
  if RemLen > 0 then
    Remaining.CopyFrom(Self, RemLen);

  Result := PacketClasses[Typ].Create(Typ, Flags, Remaining);
end;

function TMQTTStream.CopyTo(Dest: TStream; Size: Int64): Int64;
begin
  Result := Dest.CopyFrom(Self, Size);
end;

end.

