unit DungeonGenerator;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  TRoomType = (rtSmall, rtMedium, rtLarge, rtComposite);

  TRoom = class
  public
    ID: string;
    RoomType: TRoomType;
    constructor Create(const AID: string);
  end;

  TCorridor = class
  public
    ID: string;
    Width: Integer;
    constructor Create(const AID: string; AWidth: Integer);
  end;

  TTileMap = class
  public
    Width: Integer;
    Height: Integer;
    constructor Create(AWidth, AHeight: Integer);
  end;

  TDungeonGenerator = class
  private
    FSeed: Cardinal;
  public
    constructor Create(ASeed: Cardinal);
    destructor Destroy; override;
    function Generate(Level: Integer): Boolean;
  end;

implementation

{ TRoom }

constructor TRoom.Create(const AID: string);
begin
  ID := AID;
  RoomType := rtSmall;
end;

{ TCorridor }

constructor TCorridor.Create(const AID: string; AWidth: Integer);
begin
  ID := AID;
  Width := AWidth;
end;

{ TTileMap }

constructor TTileMap.Create(AWidth, AHeight: Integer);
begin
  Width := AWidth;
  Height := AHeight;
end;

{ TDungeonGenerator }

constructor TDungeonGenerator.Create(ASeed: Cardinal);
begin
  inherited Create;
  FSeed := ASeed;
end;

destructor TDungeonGenerator.Destroy;
begin
  inherited Destroy;
end;

function TDungeonGenerator.Generate(Level: Integer): Boolean;
var
  OutF: TextFile;
  JSONstub: string;
begin
  Result := False;
  JSONstub := '{"meta":{"level":' + IntToStr(Level) + ',"seed":' + IntToStr(FSeed) + '},"rooms":[],"corridors":[]}';
  try
    AssignFile(OutF, 'geometry.json');
    Rewrite(OutF);
    Writeln(OutF, JSONstub);
    CloseFile(OutF);
    Result := True;
  except
    Result := False;
  end;
end;

end.
