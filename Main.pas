unit Main;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, ExtCtrls, StdCtrls, FileCtrl, LMDPNGImage, AdvSplitter;

type
  TPacket = packed record
    // Signature 1 byte
    Signature: Byte;

    // Version 1 byte
    Version: Byte;

    // Fix type 1 byte
    FixType: Byte;

    // Date and time 8 bytes
    Year, Month, Day: Byte;
    Hours, Minutes, Seconds: Byte;
    MilliSeconds: Word;

    // Position 12 bytes
    Longitude, Latitude: LongInt;
    Altitude: LongInt;

    // Misc GPS 1 byte
    Satellites: Byte;

    // ADC 2 bytes
    BatteryVoltage: Word;

    // Accelerometer 6 bytes
    AccelX, AccelY, AccelZ: SmallInt;

    // BME280 6 bytes
    Temperature, Pressure, Humidity: SmallInt;

    // Total 2+1+8+12+1+2+6+6 = 38 bytes, so pad to 64 bytes
    // Padding: Array[1..26] of Byte;
end;

type
  TForm1 = class(TForm)
    AdvSplitter1: TAdvSplitter;
    Panel1: TPanel;
    Panel2: TPanel;
    Button1: TButton;
    Panel3: TPanel;
    Image1: TImage;
    Panel4: TPanel;
    Memo1: TMemo;
    Panel5: TPanel;
    AdvSplitter2: TAdvSplitter;
    DirectoryListBox1: TDirectoryListBox;
    FileListBox1: TFileListBox;
    DriveComboBox1: TDriveComboBox;
    pnlStatus: TPanel;
    SaveDialog1: TSaveDialog;
    procedure Panel3Resize(Sender: TObject);
    procedure FileListBox1Change(Sender: TObject);
    procedure Button1Click(Sender: TObject);
  private
    { Private declarations }
    procedure PreviewFile(FileName: String);
    procedure ExportFile(SourceFileName, TargetFileName: String);
  public
    { Public declarations }
  end;

var
  Form1: TForm1;

implementation

{$R *.dfm}

procedure TForm1.FileListBox1Change(Sender: TObject);
begin
    Memo1.Lines.Clear;
    if FileExists(FileListBox1.FileName) then begin
        if UpperCase(ExtractFileExt(FileListBox1.FileName)) = '.BIN' then begin
            pnlStatus.Caption := 'Showing ' + FileListBox1.FileName;
            PreviewFile(FileListBox1.FileName);
        end else begin
            pnlStatus.Caption := FileListBox1.FileName + ' is not a .BIN file';
        end;
    end;
end;

procedure TForm1.Panel3Resize(Sender: TObject);
begin
    Image1.Height := Panel3.ClientHeight;
    Image1.Top := 0;
    Image1.Width := Round((Image1.Height * Image1.Picture.Width) / Image1.Picture.Height);
    Image1.Left := (Panel3.ClientWidth - Image1.Width) div 2;
end;

function ConvertPacketToCSV(Packet: TPacket): String;
var
    Line: String;
begin
    with Packet do begin
        Line := Format('%.2u:%.2u:%.2u,', [Day, Month, Year]) +
                Format('%.2u:%.2u:%.2u.%.4u,', [Hours, Minutes, Seconds, MilliSeconds]) +
                Format('%.5f,%.5f,%u,', [Latitude / 10000000, Longitude / 10000000, Altitude]) +
                IntToStr(Satellites) + ',' +
                IntToStr(FixType) + ',' +
                Format('%.2f,', [BatteryVoltage / 1000]) +
                Format('%.3f,%.3f,%.3f,', [AccelX / 250, AccelY / 250, AccelZ / 200]) +
                Format('%.2f,%.1f,%.2f', [Temperature / 100, Pressure / 10, Humidity / 100]);
    end;

    Result := Line;
end;

procedure TForm1.PreviewFile(FileName: String);
var
    F: File;
    Packet: TPacket;
    Done: Boolean;
    ByteCount, BytesRemaining, Count: Integer;
begin
    Memo1.Lines.Clear;

    AssignFile(F, FileName);
    Reset(F,1);

    try
        BlockRead(F, &Packet, sizeof(Packet));
        ByteCount := 0;

        if Packet.Signature = $A5 then begin
            // Correct sig, check the version number
            if Packet.Version = 1 then begin
                pnlStatus.Caption := 'File is OK; preview above (first 64 records).  Click Export to export full file to CSV format';
                Count := 1;
                repeat
                    // Display packet
                    Memo1.Lines.Add(ConvertPacketToCSV(Packet));

                    // Skip gap?
                    Inc(ByteCount, sizeof(Packet));
                    BytesRemaining := 512 - ByteCount;
                    if BytesRemaining < sizeof(Packet) then begin
                        Seek(F, FilePos(F)+BytesRemaining);
                        ByteCount := 0;
                    end;

                    // Next packet
                    BlockRead(F, &Packet, sizeof(Packet));
                    Done := Packet.Signature <> $A5;
                    Inc(Count);
                until Done or (Count >= 64);
            end else begin
                pnlStatus.Caption := 'Not a file from the Uputronics Data Logger';
            end;
        end else begin
            pnlStatus.Caption := 'Not a file from the Uputronics Data Logger';
        end;
    except
        pnlStatus.Caption := 'File is empty or cannot be read';
    end;

    CloseFile(F);
end;

procedure TForm1.Button1Click(Sender: TObject);
begin
    if FileExists(FileListBox1.FileName) then begin
        if SaveDialog1.Execute then begin
            ExportFile(FileListBox1.FileName, SaveDialog1.FileName);
        end;
    end;
end;

procedure TForm1.ExportFile(SourceFileName, TargetFileName: String);
var
    F1: File;
    F2: TextFile;
    Packet: TPacket;
    Done: Boolean;
    ByteCount, BytesRemaining: Integer;
begin
    AssignFile(F1, SourceFileName);
    Reset(F1,1);
    BlockRead(F1, &Packet, sizeof(Packet));

    if (Packet.Signature = $A5) and (Packet.Version = 1) then begin
        AssignFile(F2, TargetFileName);
        Rewrite(F2);

        ByteCount := 0;

        pnlStatus.Caption := 'Exporting ...';
        Application.ProcessMessages;

        repeat
            // Display packet
            WriteLn(F2, ConvertPacketToCSV(Packet));

            // Skip gap?
            Inc(ByteCount, sizeof(Packet));
            BytesRemaining := 512 - ByteCount;
            if BytesRemaining < sizeof(Packet) then begin
                Seek(F1, FilePos(F1)+BytesRemaining);
                ByteCount := 0;
            end;

            // Next packet
            BlockRead(F1, &Packet, sizeof(Packet));
            Done := Packet.Signature <> $A5;
        until Done;
        CloseFile(F2);
        pnlStatus.Caption := 'Exported OK';
    end else begin
        pnlStatus.Caption := '';
    end;
    CloseFile(F1);
end;



end.
