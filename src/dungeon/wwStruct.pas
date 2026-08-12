unit wwStruct;
{ Структуры уровня: комнаты, коридоры, развилки, связи и сам уровень. }

{$MODE OBJFPC}{$H+}

interface

uses
  SysUtils, Contnrs, wwCore, wwShapes, wwGrid;

type
  TWwStructure = class
  protected
    FId: Integer;
    FCells: TWwPointList;
  public
    constructor Create(AId: Integer);
    destructor Destroy; override;
    function CenterX: Integer;
    function CenterY: Integer;
    function TypeName: string; virtual; abstract;
    property Id: Integer read FId;
    property Cells: TWwPointList read FCells;
  end;

  TWwRoom = class(TWwStructure)
  private
    FKind: TWwRoomKind;
    FShape: TWwShape;
    FX0, FY0: Integer;
    FConnections: TWwIntList;
  public
    constructor Create(AId: Integer; AKind: TWwRoomKind; AShape: TWwShape; AX0, AY0: Integer);
    destructor Destroy; override;
    function TypeName: string; override;
    function KindName: string;
    function RequiredRank: Integer;
    function SizeMetric: Integer;
    property Kind: TWwRoomKind read FKind;
    property Shape: TWwShape read FShape;
    property X0: Integer read FX0;
    property Y0: Integer read FY0;
    property Connections: TWwIntList read FConnections;
  end;

  TWwCorridor = class(TWwStructure)
  private
    FRank: Integer;
    FFromId, FToId: Integer;
    FPath: TWwPointList;
  public
    constructor Create(AId, ARank, AFromId, AToId: Integer);
    destructor Destroy; override;
    function TypeName: string; override;
    function RankName: string;
    function CodeForRank: Byte;
    property Rank: Integer read FRank;
    property FromId: Integer read FFromId;
    property ToId: Integer read FToId write FToId;
    property Path: TWwPointList read FPath;
  end;

  TWwFork = class(TWwStructure)
  private
    FRank: Integer;
  public
    constructor Create(AId, ARank: Integer);
    function TypeName: string; override;
    property Rank: Integer read FRank;
  end;

  TWwLink = class
  private
    FA, FB: Integer;
    FKind: TWwLinkKind;
  public
    constructor Create(AA, AB: Integer; AKind: TWwLinkKind);
    function KindName: string;
    property A: Integer read FA;
    property B: Integer read FB;
    property Kind: TWwLinkKind read FKind;
  end;

  TWwLevel = class
  private
    FNumber: Integer;
    FSeed: QWord;
    FGrid: TWwGrid;
    FStructures: TFPObjectList;
    FLinks: TFPObjectList;
    FStairUpX, FStairUpY, FStairDownX, FStairDownY: Integer;
    function GetStructure(AIndex: Integer): TWwStructure;
  public
    constructor Create(ANumber: Integer; ASeed: QWord);
    destructor Destroy; override;
    procedure AddStructure(AStructure: TWwStructure);
    procedure AddLink(AA, AB: Integer; AKind: TWwLinkKind);
    function HasLink(AA, AB: Integer): Boolean;
    function StructureById(AId: Integer): TWwStructure;
    function RoomById(AId: Integer): TWwRoom;
    function StructureCount: Integer;
    function LinkCount: Integer;
    function LinkAt(AIndex: Integer): TWwLink;
    procedure ReplaceGrid(AGrid: TWwGrid);
    procedure SetStairs(AUpX, AUpY, ADownX, ADownY: Integer);
    property Number: Integer read FNumber;
    property Seed: QWord read FSeed;
    property Grid: TWwGrid read FGrid write FGrid;
    property Structures[AIndex: Integer]: TWwStructure read GetStructure;
    property StairUpX: Integer read FStairUpX write FStairUpX;
    property StairUpY: Integer read FStairUpY write FStairUpY;
    property StairDownX: Integer read FStairDownX write FStairDownX;
    property StairDownY: Integer read FStairDownY write FStairDownY;
  end;

implementation

{ TWwStructure }

constructor TWwStructure.Create(AId: Integer);
begin
  inherited Create;
  FId := AId;
  FCells := TWwPointList.Create;
end;

destructor TWwStructure.Destroy;
begin
  FCells.Free;
  inherited Destroy;
end;

function TWwStructure.CenterX: Integer;
var
  i, s: Integer;
begin
  if FCells.Count = 0 then
  begin
    Result := 0;
    Exit;
  end;
  s := 0;
  for i := 0 to FCells.Count - 1 do s := s + FCells.X[i];
  Result := s div FCells.Count;
end;

function TWwStructure.CenterY: Integer;
var
  i, s: Integer;
begin
  if FCells.Count = 0 then
  begin
    Result := 0;
    Exit;
  end;
  s := 0;
  for i := 0 to FCells.Count - 1 do s := s + FCells.Y[i];
  Result := s div FCells.Count;
end;

{ TWwRoom }

constructor TWwRoom.Create(AId: Integer; AKind: TWwRoomKind; AShape: TWwShape; AX0, AY0: Integer);
begin
  inherited Create(AId);
  FKind := AKind;
  FShape := AShape;
  FX0 := AX0;
  FY0 := AY0;
  FConnections := TWwIntList.Create;
end;

destructor TWwRoom.Destroy;
begin
  FShape.Free;
  FConnections.Free;
  inherited Destroy;
end;

function TWwRoom.TypeName: string;
begin
  Result := 'room';
end;

function TWwRoom.KindName: string;
begin
  case FKind of
    wrkSmall: Result := 'small';
    wrkMedium: Result := 'medium';
  else
    Result := 'large';
  end;
end;

function TWwRoom.RequiredRank: Integer;
begin
  case FKind of
    wrkSmall: Result := 1;
    wrkMedium: Result := 2;
  else
    Result := 3;
  end;
end;

function TWwRoom.SizeMetric: Integer;
begin
  Result := FShape.SizeMetric;
end;

{ TWwCorridor }

constructor TWwCorridor.Create(AId, ARank, AFromId, AToId: Integer);
begin
  inherited Create(AId);
  FRank := ARank;
  FFromId := AFromId;
  FToId := AToId;
  FPath := TWwPointList.Create;
end;

destructor TWwCorridor.Destroy;
begin
  FPath.Free;
  inherited Destroy;
end;

function TWwCorridor.TypeName: string;
begin
  Result := 'corridor';
end;

function TWwCorridor.RankName: string;
begin
  case FRank of
    1: Result := 'minor';
    2: Result := 'secondary';
  else
    Result := 'main';
  end;
end;

function TWwCorridor.CodeForRank: Byte;
begin
  case FRank of
    1: Result := WW_COR_MINOR;
    2: Result := WW_COR_SECOND;
  else
    Result := WW_COR_MAIN;
  end;
end;

{ TWwFork }

constructor TWwFork.Create(AId, ARank: Integer);
begin
  inherited Create(AId);
  FRank := ARank;
end;

function TWwFork.TypeName: string;
begin
  Result := 'fork';
end;

{ TWwLink }

constructor TWwLink.Create(AA, AB: Integer; AKind: TWwLinkKind);
begin
  inherited Create;
  FA := AA;
  FB := AB;
  FKind := AKind;
end;

function TWwLink.KindName: string;
begin
  case FKind of
    wlkPortal: Result := 'portal';
    wlkJunction: Result := 'junction';
  else
    Result := 'fork';
  end;
end;

{ TWwLevel }

constructor TWwLevel.Create(ANumber: Integer; ASeed: QWord);
begin
  inherited Create;
  FNumber := ANumber;
  FSeed := ASeed;
  FGrid := nil;
  FStructures := TFPObjectList.Create(True);
  FLinks := TFPObjectList.Create(True);
  FStairUpX := -1; FStairUpY := -1; FStairDownX := -1; FStairDownY := -1;
end;

destructor TWwLevel.Destroy;
begin
  FStructures.Free;
  FLinks.Free;
  if FGrid <> nil then FGrid.Free;
  inherited Destroy;
end;

procedure TWwLevel.AddStructure(AStructure: TWwStructure);
begin
  FStructures.Add(AStructure);
end;

procedure TWwLevel.AddLink(AA, AB: Integer; AKind: TWwLinkKind);
begin
  if AA = AB then Exit;
  if HasLink(AA, AB) then Exit;
  FLinks.Add(TWwLink.Create(AA, AB, AKind));
end;

function TWwLevel.HasLink(AA, AB: Integer): Boolean;
var
  i: Integer;
  l: TWwLink;
begin
  for i := 0 to FLinks.Count - 1 do
  begin
    l := TWwLink(FLinks[i]);
    if ((l.A = AA) and (l.B = AB)) or ((l.A = AB) and (l.B = AA)) then
    begin
      Result := True;
      Exit;
    end;
  end;
  Result := False;
end;

function TWwLevel.GetStructure(AIndex: Integer): TWwStructure;
begin
  Result := TWwStructure(FStructures[AIndex]);
end;

function TWwLevel.StructureById(AId: Integer): TWwStructure;
var
  i: Integer;
begin
  for i := 0 to FStructures.Count - 1 do
    if TWwStructure(FStructures[i]).Id = AId then
    begin
      Result := TWwStructure(FStructures[i]);
      Exit;
    end;
  Result := nil;
end;

function TWwLevel.RoomById(AId: Integer): TWwRoom;
var
  s: TWwStructure;
begin
  s := StructureById(AId);
  if (s <> nil) and (s is TWwRoom) then Result := TWwRoom(s) else Result := nil;
end;

function TWwLevel.StructureCount: Integer;
begin
  Result := FStructures.Count;
end;

function TWwLevel.LinkCount: Integer;
begin
  Result := FLinks.Count;
end;

function TWwLevel.LinkAt(AIndex: Integer): TWwLink;
begin
  Result := TWwLink(FLinks[AIndex]);
end;

procedure TWwLevel.ReplaceGrid(AGrid: TWwGrid);
begin
  if FGrid <> nil then FGrid.Free;
  FGrid := AGrid;
end;

procedure TWwLevel.SetStairs(AUpX, AUpY, ADownX, ADownY: Integer);
begin
  FStairUpX := AUpX;
  FStairUpY := AUpY;
  FStairDownX := ADownX;
  FStairDownY := ADownY;
end;

end.
