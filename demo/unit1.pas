unit Unit1;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  SynEdit, SynEditKeyCmds, mqtt, inifiles, TypInfo;

type

  { TForm1 }

  TForm1 = class(TForm)
    ButtonConnect: TButton;
    ButtonSubscribe: TButton;
    ButtonDisconnect: TButton;
    ButtonPublish: TButton;
    EditRespTopic: TLabeledEdit;
    EditPubTopic: TLabeledEdit;
    EditPubMessage: TLabeledEdit;
    EditCorrelData: TLabeledEdit;
    EditUser: TLabeledEdit;
    EditPass: TLabeledEdit;
    EditHost: TLabeledEdit;
    EditPort: TLabeledEdit;
    EditID: TLabeledEdit;
    EditTopic: TLabeledEdit;
    SynEdit1: TSynEdit;
    procedure ButtonConnectClick(Sender: TObject);
    procedure ButtonDisconnectClick(Sender: TObject);
    procedure ButtonPublishClick(Sender: TObject);
    procedure ButtonSubscribeClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private
    FClient: TMQTTClient;
    Ini: TIniFile;
    procedure Debug(Txt: String);
    procedure OnDisconnect(Client: TMQTTClient);
    procedure OnConnect(Client: TMQTTClient);
    procedure OnRx(Client: TMQTTClient; Topic, Message, RespTopic: String; CorrelData: TBytes);
  public

  end;

var
  Form1: TForm1;

implementation

{$R *.lfm}

{ TForm1 }

procedure TForm1.FormCreate(Sender: TObject);
begin
  Ini := TIniFile.Create('mqtt.ini');
  EditHost.Text := Ini.ReadString('server', 'host', '');
  EditPort.Text := Ini.ReadString('server', 'port', '');
  EditID.Text := Ini.ReadString('server', 'id', '');
  EditUser.Text := Ini.ReadString('server', 'user', '');
  EditPass.Text := Ini.ReadString('server', 'pass', '');
  EditTopic.Text := Ini.ReadString('subscribe', 'topic', '');
  EditPubTopic.Text := Ini.ReadString('publish', 'topic', '');
  EditPubMessage.Text := Ini.ReadString('publish', 'message', '');
  EditRespTopic.Text := Ini.ReadString('publish', 'resptopic', '');
  EditCorrelData.Text := Ini.ReadString('publish', 'correldata', '');

  FClient := TMQTTClient.Create(Self);
  FClient.OnDebug := @Debug;
  FClient.OnDisconnect := @OnDisconnect;
  FClient.OnConnect := @OnConnect;
end;

procedure TForm1.FormDestroy(Sender: TObject);
begin
  Ini.Free;
end;

procedure TForm1.ButtonConnectClick(Sender: TObject);
var
  Res: TMQTTError;
begin
  Ini.WriteString('server', 'host', EditHost.Text);
  Ini.WriteString('server', 'port', EditPort.Text);
  Ini.WriteString('server', 'id', EditID.Text);
  Ini.WriteString('server', 'user', EditUser.Text);
  Ini.WriteString('server', 'pass', EditPass.Text);
  Res := FClient.Connect(EditHost.Text, StrToIntDef(EditPort.Text, 1883), EditID.Text, EditUser.Text, EditPass.Text);
  if Res <> mqeNoError then
    Debug(Format('connect: %s', [GetEnumName(TypeInfo(TMQTTError), Ord(Res))]));
end;

procedure TForm1.ButtonDisconnectClick(Sender: TObject);
begin
  FClient.Disconect;
end;

procedure TForm1.ButtonPublishClick(Sender: TObject);
var
  Res: TMQTTError;
begin
  Ini.WriteString('publish', 'topic', EditPubTopic.Text);
  Ini.WriteString('publish', 'message', EditPubMessage.Text);
  Ini.WriteString('publish', 'resptopic', EditRespTopic.Text);
  Ini.WriteString('publish', 'correldata', EditCorrelData.Text);
  Res := FClient.Publish(EditPubTopic.Text, EditPubMessage.Text, EditRespTopic.Text,
    TBytes(EditCorrelData.Text), 0, False);
  if Res <> mqeNoError then
    Debug(Format('publish: %s', [GetEnumName(TypeInfo(TMQTTError), Ord(Res))]));
end;

procedure TForm1.ButtonSubscribeClick(Sender: TObject);
var
  Res: TMQTTError;
begin
  Ini.WriteString('subscribe', 'topic', EditTopic.Text);
  Res := FClient.Subscribe(EditTopic.Text, @OnRx);
  if Res <> mqeNoError then
    Debug(Format('subscribe: %s', [GetEnumName(TypeInfo(TMQTTError), Ord(Res))]));
end;

procedure TForm1.Debug(Txt: String);
begin
  SynEdit1.Append(Txt);
  SynEdit1.ExecuteCommand(ecEditorBottom, #0, nil);
  SynEdit1.ExecuteCommand(ecLineStart, #0, nil);
end;

procedure TForm1.OnDisconnect(Client: TMQTTClient);
begin
  Debug('OnDisconnect');
end;

procedure TForm1.OnConnect(Client: TMQTTClient);
begin
  Debug('OnConnect');
end;

procedure TForm1.OnRx(Client: TMQTTClient; Topic, Message, RespTopic: String; CorrelData: TBytes);
var
  B: Byte;
  S: String;
begin
  Debug(Format('OnRX: %s = %s', [Topic, Message]));
  if RespTopic <> '' then
    Debug(Format('OnRX: Response Topic: %s', [RespTopic]));
  if Length(CorrelData) > 0 then begin
    S := '';
    for B in CorrelData do
      S += IntToHex(B, 2) + ' ';
    Debug(Format('OnRX: Correlation Data: %s', [S]));
  end;
end;

end.

