unit Unit1;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls, Spin,
  SynEdit, SynEditKeyCmds, mqtt, inifiles, TypInfo, SynEditMiscClasses, opensslsockets;

type

  { TForm1 }

  TForm1 = class(TForm)
    ButtonConnect: TButton;
    ButtonUnsubscribe: TButton;
    ButtonSubscribe: TButton;
    ButtonDisconnect: TButton;
    ButtonPublish: TButton;
    CheckBoxSSL: TCheckBox;
    ComboBoxSubs: TComboBox;
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
    SpinEditSubID: TSpinEdit;
    SynEdit1: TSynEdit;
    procedure ButtonConnectClick(Sender: TObject);
    procedure ButtonDisconnectClick(Sender: TObject);
    procedure ButtonPublishClick(Sender: TObject);
    procedure ButtonSubscribeClick(Sender: TObject);
    procedure ButtonUnsubscribeClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private
    FClient: TMQTTClient;
    Ini: TIniFile;
    procedure Debug(Txt: String);
    procedure OnDisconnect(Client: TMQTTClient);
    procedure OnConnect(Client: TMQTTClient);
    procedure OnReceive(Client: TMQTTClient; Topic, Message, RespTopic: String; CorrelData: TBytes; ID: UInt32);
    procedure OnVerifySSL(Clinet: TMQTTClient; Handler: TOpenSSLSocketHandler; var Allow: Boolean);
    procedure LogLineColor(Sender: TObject; Line: integer; var Special: boolean; Markup: TSynSelectedColor);
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
  CheckBoxSSL.Checked := Ini.ReadBool('server', 'ssl', False);
  EditTopic.Text := Ini.ReadString('subscribe', 'topic', '');
  EditPubTopic.Text := Ini.ReadString('publish', 'topic', '');
  EditPubMessage.Text := Ini.ReadString('publish', 'message', '');
  EditRespTopic.Text := Ini.ReadString('publish', 'resptopic', '');
  EditCorrelData.Text := Ini.ReadString('publish', 'correldata', '');

  FClient := TMQTTClient.Create(Self);
  FClient.OnDebug := @Debug;
  FClient.OnDisconnect := @OnDisconnect;
  FClient.OnConnect := @OnConnect;
  FClient.OnVerifySSL := @OnVerifySSL;
  FClient.OnReceive := @OnReceive;
  if FileExists('client.crt') and FileExists('client.key') then begin
    FClient.ClientCert := 'client.crt';
    FClient.ClientKey := 'client.key';
  end;

  {$ifdef windows}
  SynEdit1.Font.Name := 'Courier New';
  {$else}
  SynEdit1.Font.Name := 'DejaVu Sans Mono';
  {$endif}
  SynEdit1.OnSpecialLineMarkup := @LogLineColor;
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
  Ini.WriteBool('server', 'ssl', CheckBoxSSL.Checked);
  Res := FClient.Connect(EditHost.Text, StrToIntDef(EditPort.Text, 1883),
    EditID.Text, EditUser.Text, EditPass.Text, CheckBoxSSL.Checked, False);
  if Res <> mqeNoError then
    Debug(Format('connect: %s', [GetEnumName(TypeInfo(TMQTTError), Ord(Res))]));
end;

procedure TForm1.ButtonDisconnectClick(Sender: TObject);
begin
  FClient.Disconect;
  ComboBoxSubs.Clear;
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
    TBytes(EditCorrelData.Text), 1, False);
  if Res <> mqeNoError then
    Debug(Format('publish: %s', [GetEnumName(TypeInfo(TMQTTError), Ord(Res))]));
end;

procedure TForm1.ButtonSubscribeClick(Sender: TObject);
var
  Res: TMQTTError;
  ID: UInt32;
begin
  Ini.WriteString('subscribe', 'topic', EditTopic.Text);
  ID := SpinEditSubID.Value;
  if ID > 0 then
    SpinEditSubID.Value := ID + 1;
  Res := FClient.Subscribe(EditTopic.Text, ID);
  if Res <> mqeNoError then
    Debug(Format('subscribe: %s', [GetEnumName(TypeInfo(TMQTTError), Ord(Res))]))
  else begin
    ComboBoxSubs.Items.Add(EditTopic.Text);
    ComboBoxSubs.Text := EditTopic.Text;
  end;
end;

procedure TForm1.ButtonUnsubscribeClick(Sender: TObject);
var
  TopicFilter: String;
  Res: TMQTTError;
begin
  TopicFilter := ComboBoxSubs.Text;
  if Text <> '' then begin
    Res := FClient.Unsubscribe(TopicFilter);
    if ComboBoxSubs.ItemIndex >= 0 then begin
      ComboBoxSubs.Items.Delete(ComboBoxSubs.ItemIndex);
      ComboBoxSubs.ItemIndex := 0;
    end
    else
      Debug(Format('unsubscribe: %s', [GetEnumName(TypeInfo(TMQTTError), Ord(Res))]));  end;
end;

procedure TForm1.Debug(Txt: String);
var
  Lines: array of String;
  Line: String;
begin
  Lines := Txt.Split(LineEnding);
  for Line in Lines do
    SynEdit1.Append(Line);
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

procedure TForm1.OnReceive(Client: TMQTTClient; Topic, Message, RespTopic: String; CorrelData: TBytes; ID: UInt32);
var
  B: Byte;
  S: String;
begin
  Debug(Format('OnReceive: ID:%d, %s = %s', [ID, Topic, Message]));
  if RespTopic <> '' then
    Debug(Format('OnReceive: Response Topic: %s', [RespTopic]));
  if Length(CorrelData) > 0 then begin
    S := '';
    for B in CorrelData do
      S += IntToHex(B, 2) + ' ';
    Debug(Format('OnReceive: Correlation Data: %s', [S]));
  end;
end;

procedure TForm1.OnVerifySSL(Clinet: TMQTTClient; Handler: TOpenSSLSocketHandler; var Allow: Boolean);
var
  C: Char;
  S: String = '';
begin
  for C in Handler.SSL.PeerFingerprint('SHA256') do begin
    S += IntToHex(Ord(C), 2);
  end;
  Debug('OnVerifySSL cert fingerprint: ' + S);
  Allow := True;
end;

procedure TForm1.LogLineColor(Sender: TObject; Line: integer; var Special: boolean; Markup: TSynSelectedColor);
var
  S: String;

  function Mix(CA, CB: TColor; Ratio: Byte): TColor;
  var
    R, G, B: Byte;
    Ratio_: Byte;
  begin
    CA := ColorToRGB(CA);
    CB := ColorToRGB(CB);
    Ratio_ := 100 - Ratio;
    R := (Ratio_ * Red(CA)   + Ratio * Red(CB)) div 100;
    G := (Ratio_ * Green(CA) + Ratio * Green(CB)) div 100;
    B := (Ratio_ * Blue(CA)  + Ratio * Blue(CB)) div 100;
    Result := RGBToColor(R, G, B);
  end;

begin
  S := SynEdit1.Lines[Line - 1];
  if Pos('[', S) = 1 then begin
    Special := True;
    Markup.Foreground := Mix(SynEdit1.Color, SynEdit1.Font.Color, 40);
    Markup.Background := clNone;
  end;
end;

end.

