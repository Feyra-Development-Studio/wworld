unit wwJson;
{ Основное хранилище — JSON с графом-инструкцией подземелья.

  В файле лежит не растр, а то, из чего растр однозначно восстанавливается:
  seed, комнаты со спецификацией формы (тип и размеры частей), осевые линии
  коридоров с рангом, узлы развилок, связи и лестницы. Маски комнат и клетки
  коридоров считает геометрия на R — хранить их незачем, они выводимы.

  CSV остаётся человекочитаемой выгрузкой для проверки глазами и валидатором
  и пишется только с флагом --test. }

{$MODE OBJFPC}{$H+}

interface

uses
  SysUtils, Classes, fpjson, jsonparser, jsonscanner, Contnrs, wwCore, wwShapes, wwGrid, wwStruct;

type
  TWwJsonWriter = class
  private
    FRoot: TJSONObject;
    FLevels: TJSONArray;
    FFileName: string;
    function SpecToJson(ASpec: TWwShapeSpec): TJSONObject;
    function PathToJson(APath: TWwPointList): TJSONArray;
  public
    constructor Create(const AFileName: string; ASeed: QWord);
    destructor Destroy; override;
    procedure AddLevel(ALevel: TWwLevel);
    procedure Flush;
  end;

  TWwJsonReader = class
  private
    FRoot: TJSONObject;
    FLevels: TJSONArray;
    FSeed: QWord;
    function JsonToSpec(AObj: TJSONObject): TWwShapeSpec;
    function KindFromName(const AName: string): TWwRoomKind;
    function LinkKindFromName(const AName: string): TWwLinkKind;
  public
    constructor Create(const AFileName: string);
    destructor Destroy; override;
    function LevelCount: Integer;
    { Возвращает уровень со структурами и пустой сеткой нужного размера.
      Заполняет её TWwRebuilder. }
    function LevelAt(AIndex: Integer): TWwLevel;
    property Seed: QWord read FSeed;
  end;

implementation

{ TWwJsonWriter }

constructor TWwJsonWriter.Create(const AFileName: string; ASeed: QWord);
begin
  inherited Create;
  FFileName := AFileName;
  FRoot := TJSONObject.Create;
  FLevels := TJSONArray.Create;
  FRoot.Add('format', 'wworld-dungeon');
  FRoot.Add('version', 1);
  FRoot.Add('seed', TJSONString.Create(IntToStr(ASeed)));
  FRoot.Add('note', 'граф-инструкция: растр восстанавливается геометрией на R');
  FRoot.Add('levels', FLevels);
end;

destructor TWwJsonWriter.Destroy;
begin
  FRoot.Free;
  inherited Destroy;
end;

function TWwJsonWriter.SpecToJson(ASpec: TWwShapeSpec): TJSONObject;
var
  parts: TJSONArray;
  part: TJSONObject;
  i: Integer;
begin
  Result := TJSONObject.Create;
  Result.Add('shape', ASpec.ShapeName);
  if not ASpec.IsComposite then
  begin
    Result.Add('w', ASpec.PartW(0));
    Result.Add('h', ASpec.PartH(0));
    Exit;
  end;
  parts := TJSONArray.Create;
  for i := 0 to ASpec.PartCount - 1 do
  begin
    part := TJSONObject.Create;
    part.Add('type', ASpec.PartType(i));
    part.Add('w', ASpec.PartW(i));
    part.Add('h', ASpec.PartH(i));
    part.Add('ox', ASpec.PartOX(i));
    part.Add('oy', ASpec.PartOY(i));
    parts.Add(part);
  end;
  Result.Add('parts', parts);
end;

function TWwJsonWriter.PathToJson(APath: TWwPointList): TJSONArray;
var
  i: Integer;
  pt: TJSONArray;
begin
  Result := TJSONArray.Create;
  for i := 0 to APath.Count - 1 do
  begin
    pt := TJSONArray.Create;
    pt.Add(APath.X[i]);
    pt.Add(APath.Y[i]);
    Result.Add(pt);
  end;
end;

procedure TWwJsonWriter.AddLevel(ALevel: TWwLevel);
var
  lv, obj, stairs: TJSONObject;
  rooms, corridors, forks, links: TJSONArray;
  i: Integer;
  s: TWwStructure;
  r: TWwRoom;
  c: TWwCorridor;
  l: TWwLink;
begin
  lv := TJSONObject.Create;
  lv.Add('level', ALevel.Number);
  lv.Add('width', ALevel.Grid.W);
  lv.Add('height', ALevel.Grid.H);

  stairs := TJSONObject.Create;
  stairs.Add('up_x', ALevel.StairUpX);
  stairs.Add('up_y', ALevel.StairUpY);
  stairs.Add('down_x', ALevel.StairDownX);
  stairs.Add('down_y', ALevel.StairDownY);
  lv.Add('stairs', stairs);

  rooms := TJSONArray.Create;
  corridors := TJSONArray.Create;
  forks := TJSONArray.Create;
  links := TJSONArray.Create;

  for i := 0 to ALevel.StructureCount - 1 do
  begin
    s := ALevel.Structures[i];
    if s is TWwRoom then
    begin
      r := TWwRoom(s);
      obj := SpecToJson(r.Spec);
      obj.Add('id', r.Id);
      obj.Add('kind', r.KindName);
      obj.Add('x', r.X0);
      obj.Add('y', r.Y0);
      rooms.Add(obj);
    end
    else if s is TWwCorridor then
    begin
      c := TWwCorridor(s);
      obj := TJSONObject.Create;
      obj.Add('id', c.Id);
      obj.Add('rank', c.Rank);
      obj.Add('from', c.FromId);
      obj.Add('to', c.ToId);
      obj.Add('path', PathToJson(c.Path));
      corridors.Add(obj);
    end
    else if s is TWwFork then
    begin
      obj := TJSONObject.Create;
      obj.Add('id', s.Id);
      obj.Add('rank', TWwFork(s).Rank);
      obj.Add('x', s.Cells.X[0]);
      obj.Add('y', s.Cells.Y[0]);
      forks.Add(obj);
    end;
  end;

  for i := 0 to ALevel.LinkCount - 1 do
  begin
    l := ALevel.LinkAt(i);
    obj := TJSONObject.Create;
    obj.Add('a', l.A);
    obj.Add('b', l.B);
    obj.Add('kind', l.KindName);
    links.Add(obj);
  end;

  lv.Add('rooms', rooms);
  lv.Add('corridors', corridors);
  lv.Add('forks', forks);
  lv.Add('links', links);
  FLevels.Add(lv);
end;

procedure TWwJsonWriter.Flush;
var
  sl: TStringList;
  dir: string;
begin
  dir := ExtractFileDir(FFileName);
  if (dir <> '') and (not DirectoryExists(dir)) then ForceDirectories(dir);
  sl := TStringList.Create;
  try
    sl.Text := FRoot.FormatJSON([foSingleLineArray]);
    sl.SaveToFile(FFileName);
  finally
    sl.Free;
  end;
end;

{ TWwJsonReader }

constructor TWwJsonReader.Create(const AFileName: string);
var
  sl: TStringList;
  parser: TJSONParser;
  data: TJSONData;
begin
  inherited Create;
  if not FileExists(AFileName) then
    raise Exception.CreateFmt('не найден файл подземелья: %s', [AFileName]);
  sl := TStringList.Create;
  try
    sl.LoadFromFile(AFileName);
    parser := TJSONParser.Create(sl.Text, [joUTF8]);
    try
      data := parser.Parse;
    finally
      parser.Free;
    end;
  finally
    sl.Free;
  end;
  if not (data is TJSONObject) then
  begin
    data.Free;
    raise Exception.CreateFmt('%s: ожидался объект JSON', [AFileName]);
  end;
  FRoot := TJSONObject(data);
  FSeed := StrToQWordDef(FRoot.Get('seed', '0'), 0);
  FLevels := FRoot.Arrays['levels'];
end;

destructor TWwJsonReader.Destroy;
begin
  FRoot.Free;
  inherited Destroy;
end;

function TWwJsonReader.LevelCount: Integer;
begin
  Result := FLevels.Count;
end;

function TWwJsonReader.KindFromName(const AName: string): TWwRoomKind;
begin
  if AName = 'small' then Result := wrkSmall
  else if AName = 'medium' then Result := wrkMedium
  else Result := wrkLarge;
end;

function TWwJsonReader.LinkKindFromName(const AName: string): TWwLinkKind;
begin
  if AName = 'portal' then Result := wlkPortal
  else if AName = 'junction' then Result := wlkJunction
  else Result := wlkFork;
end;

function TWwJsonReader.JsonToSpec(AObj: TJSONObject): TWwShapeSpec;
var
  parts: TJSONArray;
  part: TJSONObject;
  i: Integer;
begin
  Result := TWwShapeSpec.Create;
  if AObj.Get('shape', '') <> 'composite' then
  begin
    Result.AddPart(AObj.Get('shape', 'rect'), AObj.Get('w', 3), AObj.Get('h', 3), 0, 0);
    Exit;
  end;
  parts := AObj.Arrays['parts'];
  for i := 0 to parts.Count - 1 do
  begin
    part := parts.Objects[i];
    Result.AddPart(part.Get('type', 'rect'), part.Get('w', 3), part.Get('h', 3),
      part.Get('ox', 0), part.Get('oy', 0));
  end;
end;

function TWwJsonReader.LevelAt(AIndex: Integer): TWwLevel;
var
  lv: TJSONObject;
  arr: TJSONArray;
  obj: TJSONObject;
  i, j: Integer;
  level: TWwLevel;
  room: TWwRoom;
  cor: TWwCorridor;
  fork: TWwFork;
  pt: TJSONArray;
begin
  lv := FLevels.Objects[AIndex];
  level := TWwLevel.Create(lv.Get('level', 0), FSeed);
  level.Grid := TWwGrid.Create(lv.Get('width', 1), lv.Get('height', 1));

  obj := lv.Objects['stairs'];
  level.SetStairs(obj.Get('up_x', -1), obj.Get('up_y', -1),
                  obj.Get('down_x', -1), obj.Get('down_y', -1));

  arr := lv.Arrays['rooms'];
  for i := 0 to arr.Count - 1 do
  begin
    obj := arr.Objects[i];
    { форма здесь ещё не построена: маску попросит TWwRebuilder }
    room := TWwRoom.Create(obj.Get('id', 0), KindFromName(obj.Get('kind', 'small')),
      JsonToSpec(obj), nil, obj.Get('x', 0), obj.Get('y', 0));
    level.AddStructure(room);
  end;

  arr := lv.Arrays['forks'];
  for i := 0 to arr.Count - 1 do
  begin
    obj := arr.Objects[i];
    fork := TWwFork.Create(obj.Get('id', 0), obj.Get('rank', 2));
    for j := 0 to obj.Get('rank', 2) * obj.Get('rank', 2) - 1 do
      fork.Cells.Add(obj.Get('x', 0) + j mod obj.Get('rank', 2),
                     obj.Get('y', 0) + j div obj.Get('rank', 2));
    level.AddStructure(fork);
  end;

  arr := lv.Arrays['corridors'];
  for i := 0 to arr.Count - 1 do
  begin
    obj := arr.Objects[i];
    cor := TWwCorridor.Create(obj.Get('id', 0), obj.Get('rank', 1),
      obj.Get('from', 0), obj.Get('to', 0));
    pt := obj.Arrays['path'];
    for j := 0 to pt.Count - 1 do
      cor.Path.Add(pt.Arrays[j].Integers[0], pt.Arrays[j].Integers[1]);
    level.AddStructure(cor);
  end;

  arr := lv.Arrays['links'];
  for i := 0 to arr.Count - 1 do
  begin
    obj := arr.Objects[i];
    level.AddLink(obj.Get('a', 0), obj.Get('b', 0),
      LinkKindFromName(obj.Get('kind', 'portal')));
  end;

  Result := level;
end;

end.
