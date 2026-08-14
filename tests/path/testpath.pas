program testpath;
{ Проверка поиска пути для ходьбы указанием клетки (#10).

  Окна здесь нет и не нужно: указание клетки приходит от мыши или от касания,
  а поиск пути от способа указания не зависит. Поэтому проверка гоняется в CI
  на обычном бегунке, без BearLibTerminal и без эмулятора.

  Проверяется главное свойство: указанием достижимо ровно то же, что
  клавишами. Если правила разойдутся, игра станет вести себя по-разному в
  зависимости от того, чем в неё играют, — а по условию любого одного
  устройства ввода должно хватать.

    fpc -Mobjfpc -Sh -Fusrc/dungeon -FUbuild/tests -obuild/tests/testpath \
        tests/path/testpath.pas }

{$MODE OBJFPC}{$H+}

uses
  SysUtils, wwCore, wwGrid, wwPath;

var
  Failures: Integer = 0;
  Checks: Integer = 0;

procedure Check(ACondition: Boolean; const AName: string);
begin
  Inc(Checks);
  if ACondition then
    WriteLn('  ок    ', AName)
  else
  begin
    WriteLn('  ПЛОХО ', AName);
    Inc(Failures);
  end;
end;

{ Сетка из рисунка: '#' — камень, '.' — пол. }
function GridFromRows(const ARows: array of string): TWwGrid;
var
  x, y: Integer;
begin
  Result := TWwGrid.Create(Length(ARows[0]), Length(ARows));
  for y := 0 to High(ARows) do
    for x := 1 to Length(ARows[y]) do
      if ARows[y][x] = '.' then
        Result.PutCode(x - 1, y, WW_ROOM)
      else
        Result.PutCode(x - 1, y, WW_ROCK);
end;

{ Проходит путь от начала и возвращает, куда он привёл. }
procedure Walk(const APath: TWwPath; var AX, AY: Integer);
var
  i: Integer;
begin
  for i := 0 to High(APath) do
  begin
    Inc(AX, APath[i].DX);
    Inc(AY, APath[i].DY);
  end;
end;

procedure TestStraight;
var
  g: TWwGrid;
  p: TWwPath;
  reason: string;
  x, y: Integer;
begin
  WriteLn('прямой путь по коридору');
  g := GridFromRows(['#####', '#...#', '#####']);
  Check(WwFindPath(g, 1, 1, 3, 1, p, reason), 'путь найден');
  Check(Length(p) = 2, 'длина 2 шага, а не ' + IntToStr(Length(p)));
  x := 1; y := 1; Walk(p, x, y);
  Check((x = 3) and (y = 1), 'путь приводит в указанную клетку');
  g.Free;
end;

procedure TestDiagonal;
var
  g: TWwGrid;
  p: TWwPath;
  reason: string;
  x, y: Integer;
begin
  WriteLn('диагональ короче прямых');
  g := GridFromRows(['#####', '#...#', '#...#', '#...#', '#####']);
  Check(WwFindPath(g, 1, 1, 3, 3, p, reason), 'путь найден');
  { По прямым было бы 4 шага, по диагонали 2 — обход в ширину обязан
    выбрать короткий, иначе указание и клавиши разойдутся: клавишами
    QEZC туда доходят за два хода. }
  Check(Length(p) = 2, 'два диагональных шага, а не ' + IntToStr(Length(p)));
  x := 1; y := 1; Walk(p, x, y);
  Check((x = 3) and (y = 3), 'путь приводит в указанную клетку');
  g.Free;
end;

procedure TestWall;
var
  g: TWwGrid;
  p: TWwPath;
  reason: string;
begin
  WriteLn('указание в стену');
  g := GridFromRows(['#####', '#...#', '#####']);
  Check(not WwFindPath(g, 1, 1, 0, 0, p, reason), 'отказ');
  Check(Pos('стена', reason) > 0, 'причина названа: ' + reason);
  Check(Length(p) = 0, 'путь пуст');
  g.Free;
end;

procedure TestUnreachable;
var
  g: TWwGrid;
  p: TWwPath;
  reason: string;
begin
  WriteLn('проходимая, но отрезанная клетка');
  g := GridFromRows(['#####', '#.#.#', '#####']);
  Check(not WwFindPath(g, 1, 1, 3, 1, p, reason), 'отказ');
  Check(Pos('нет дороги', reason) > 0, 'причина названа: ' + reason);
  g.Free;
end;

procedure TestSelf;
var
  g: TWwGrid;
  p: TWwPath;
  reason: string;
begin
  WriteLn('указание на себя');
  g := GridFromRows(['###', '#.#', '###']);
  Check(WwFindPath(g, 1, 1, 1, 1, p, reason), 'успех');
  Check(Length(p) = 0, 'нулевой путь');
  g.Free;
end;

procedure TestOutside;
var
  g: TWwGrid;
  p: TWwPath;
  reason: string;
begin
  WriteLn('указание за край карты');
  g := GridFromRows(['###', '#.#', '###']);
  Check(not WwFindPath(g, 1, 1, 99, 99, p, reason), 'отказ');
  Check(Pos('за краем', reason) > 0, 'причина названа: ' + reason);
  g.Free;
end;

procedure TestDeterminism;
var
  g: TWwGrid;
  p1, p2: TWwPath;
  reason: string;
  i: Integer;
  same: Boolean;
begin
  WriteLn('повторяемость');
  g := GridFromRows(['######', '#....#', '#....#', '######']);
  WwFindPath(g, 1, 1, 4, 2, p1, reason);
  WwFindPath(g, 1, 1, 4, 2, p2, reason);
  same := Length(p1) = Length(p2);
  if same then
    for i := 0 to High(p1) do
      if (p1[i].DX <> p2[i].DX) or (p1[i].DY <> p2[i].DY) then same := False;
  Check(same, 'два одинаковых запроса дают один и тот же путь');
  g.Free;
end;

begin
  WriteLn('== поиск пути для ходьбы указанием ==');
  TestStraight;
  TestDiagonal;
  TestWall;
  TestUnreachable;
  TestSelf;
  TestOutside;
  TestDeterminism;
  WriteLn;
  WriteLn(Format('проверок %d, провалов %d', [Checks, Failures]));
  if Failures > 0 then Halt(1);
end.
