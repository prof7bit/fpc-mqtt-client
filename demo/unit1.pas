unit Unit1;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  SynEdit, SynEditKeyCmds, mqtt, inifiles;

type

  { TForm1 }

  TForm1 = class(TForm)
    ButtonConnect: TButton;
    ButtonSubscribe: TButton;
    ButtonDisconnect: TButton;
    EditUser: TLabeledEdit;
    EditPass: TLabeledEdit;
    EditHost: TLabeledEdit;
    EditPort: TLabeledEdit;
    EditID: TLabeledEdit;
    EditTopic: TLabeledEdit;
    SynEdit1: TSynEdit;
    procedure ButtonConnectClick(Sender: TObject);
    procedure ButtonDisconnectClick(Sender: TObject);
    procedure ButtonSubscribeClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private
    FClient: TMQTTClient;
    Ini: TIniFile;
    procedure Debug(Txt: String);
    procedure OnDisconnect(Client: TMQTTClient);
    procedure OnRx(Client: TMQTTClient; Topic, Message: String);
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
  FClient := TMQTTClient.Create(Self);
  FClient.OnDebug := @Debug;
  FClient.OnDisconnect := @OnDisconnect;
end;

procedure TForm1.FormDestroy(Sender: TObject);
begin
  Ini.Free;
end;

procedure TForm1.ButtonConnectClick(Sender: TObject);
begin
  Ini.WriteString('server', 'host', EditHost.Text);
  Ini.WriteString('server', 'port', EditPort.Text);
  Ini.WriteString('server', 'id', EditID.Text);
  Ini.WriteString('server', 'user', EditUser.Text);
  Ini.WriteString('server', 'pass', EditPass.Text);
  FClient.Connect(EditHost.Text, StrToIntDef(EditPort.Text, 1883), EditID.Text, EditUser.Text, EditPass.Text);
end;

procedure TForm1.ButtonDisconnectClick(Sender: TObject);
begin
  FClient.Disconect;
end;

procedure TForm1.ButtonSubscribeClick(Sender: TObject);
begin
  Ini.WriteString('subscribe', 'topic', EditTopic.Text);
  FClient.Subscribe(EditTopic.Text, @OnRx);
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

procedure TForm1.OnRx(Client: TMQTTClient; Topic, Message: String);
begin
  Debug(Format('Topic: %s Message: %s', [Topic, Message]));
end;

end.

