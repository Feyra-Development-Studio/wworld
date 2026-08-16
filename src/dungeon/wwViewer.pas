unit wwViewer;
{ Ходилка по сгенерированному подземелью.

  Два бэкенда с общим базовым классом:
    TWwConsoleViewer — терминал (unit crt), работает везде и в CI;
    TWwBltViewer     — BearLibTerminal, собирается только с -dUSE_BLT,
                       чтобы отсутствие libBearLibTerminal.so не ломало
                       сборку. Биндинг берётся из сабмодуля
                       third_party/bearlibterminal/Terminal/Include/Pascal.

  Управление: WASD / стрелки / диагонали QEZC, '>' и '<' — лестницы,
  Esc или Q — выход. }

{$MODE OBJFPC}{$H+}

interface

uses
  SysUtils, Crt, wwCore, wwGrid, wwPath, wwSource
  {$IFDEF USE_BLT}, BearLibTerminal{$ENDIF};

type
  TWwViewer = class
  protected
    FSource: TWwMapSource;
    FGrid: TWwGrid;
    FLevel, FMaxLevel: Integer;
    FPlayerX, FPlayerY: Integer;
    FStatus: string;
    FViewW, FViewH: Integer;
    function GlyphFor(ACode: Byte): Char;
    procedure LoadLevel(ANumber: Integer; AAtStairUp: Boolean);
    function TryMove(ADX, ADY: Integer): Boolean;
    procedure UseStairs;
    procedure HandleKey(AKey: Char);
    { Ходьба указанием клетки: мышью на настольных платформах, касанием на
      Android. Способ указания разный, обработка одна. }
    function WalkTo(AX, AY: Integer): Boolean;
  public
    constructor Create(ASource: TWwMapSource);
    destructor Destroy; override;
    procedure Render; virtual; abstract;
    procedure Run; virtual; abstract;
    procedure RunScript(const AMoves: string);
  end;

  TWwConsoleViewer = class(TWwViewer)
  public
    procedure Render; override;
    procedure Run; override;
  end;

  {$IFDEF USE_BLT}
  TWwBltViewer = class(TWwViewer)
  private
    function ColorFor(ACode: Byte): string;
    { Смещение видимой области. Нужно и при отрисовке, и при разборе
      указания: терминал сообщает клетку экрана, а игре нужна клетка карты. }
    procedure ViewOrigin(out AOX, AOY: Integer);
    { Щелчок мышью или касание — приходят одним и тем же событием. }
    procedure HandlePointer;
  public
    procedure Render; override;
    procedure Run; override;
    { Один кадр: разобрать накопившийся ввод и перерисовать.

      Нужен там, где своего цикла у игры быть не может: на Android кадром
      управляет система, а Run с его terminal_read внутри занял бы поток
      навсегда. Возвращает False, когда игра просит выхода. }
    function Step: Boolean;
  end;
  {$ENDIF}

implementation

constructor TWwViewer.Create(ASource: TWwMapSource);
begin
  inherited Create;
  FSource := ASource;
  FMaxLevel := FSource.LevelCount;
  FViewW := 78;
  FViewH := 22;
  FGrid := nil;
  LoadLevel(1, True);
end;

destructor TWwViewer.Destroy;
begin
  if FGrid <> nil then FGrid.Free;
  FSource.Free;
  inherited Destroy;
end;

function TWwViewer.GlyphFor(ACode: Byte): Char;
begin
  case ACode of
    WW_ROCK: Result := ' ';
    WW_WALL: Result := '#';
    WW_ROOM: Result := '.';
    WW_COR_MINOR: Result := ':';
    WW_COR_SECOND: Result := '=';
    WW_COR_MAIN: Result := '%';
    WW_JUNCTION: Result := '+';
    WW_FORK: Result := '*';
    WW_STAIR_UP: Result := '<';
    WW_STAIR_DOWN: Result := '>';
  else
    Result := ' ';
  end;
end;

procedure TWwViewer.LoadLevel(ANumber: Integer; AAtStairUp: Boolean);
var
  g: TWwGrid;
begin
  if (ANumber < 1) or (ANumber > FMaxLevel) then Exit;
  g := FSource.LoadGrid(ANumber);
  if g = nil then Exit;
  if FGrid <> nil then FGrid.Free;
  FGrid := g;
  FLevel := ANumber;
  if AAtStairUp then
  begin
    FPlayerX := FSource.StairUpX(ANumber);
    FPlayerY := FSource.StairUpY(ANumber);
  end
  else
  begin
    FPlayerX := FSource.StairDownX(ANumber);
    FPlayerY := FSource.StairDownY(ANumber);
  end;
  FStatus := Format('этаж %d/%d, поле %dx%d', [FLevel, FMaxLevel, FGrid.W, FGrid.H]);
end;

function TWwViewer.TryMove(ADX, ADY: Integer): Boolean;
begin
  Result := False;
  if not FGrid.IsWalkable(FPlayerX + ADX, FPlayerY + ADY) then
  begin
    FStatus := 'путь перекрыт';
    Exit;
  end;
  Inc(FPlayerX, ADX);
  Inc(FPlayerY, ADY);
  FStatus := Format('этаж %d/%d  x=%d y=%d', [FLevel, FMaxLevel, FPlayerX, FPlayerY]);
  Result := True;
end;

procedure TWwViewer.UseStairs;
var
  c: Byte;
begin
  c := FGrid.CodeAt(FPlayerX, FPlayerY);
  if c = WW_STAIR_DOWN then
  begin
    if FLevel < FMaxLevel then
      LoadLevel(FLevel + 1, True)
    else
      FStatus := 'это самый нижний этаж';
  end
  else if c = WW_STAIR_UP then
  begin
    if FLevel > 1 then
      LoadLevel(FLevel - 1, False)
    else
      FStatus := 'выход наружу';
  end
  else
    FStatus := 'здесь нет лестницы';
end;

function TWwViewer.WalkTo(AX, AY: Integer): Boolean;
var
  path: TWwPath;
  reason: string;
  i: Integer;
begin
  Result := False;

  { Указали на клетку, где стоим: если под ногами лестница — это она и есть.
    Так лестница работает и без клавиатуры, а без этого на Android до неё
    было бы не добраться. }
  if (AX = FPlayerX) and (AY = FPlayerY) then
  begin
    UseStairs;
    Result := True;
    Exit;
  end;

  if not WwFindPath(FGrid, FPlayerX, FPlayerY, AX, AY, path, reason) then
  begin
    { Причину показываем обязательно: молчание неотличимо от промаха мимо
      клетки, а пальцем промахиваются постоянно. }
    FStatus := reason;
    Exit;
  end;

  for i := 0 to High(path) do
    if not TryMove(path[i].DX, path[i].DY) then
    begin
      { Такого быть не должно: путь построен по тому же правилу перехода.
        Если случилось — значит правила разошлись, и молчать об этом нельзя. }
      FStatus := 'путь оборвался на полушаге';
      Exit;
    end;

  Result := True;
end;

procedure TWwViewer.HandleKey(AKey: Char);
var
  k: Char;
begin
  k := LowerCase(AKey);
  case k of
    'w': TryMove(0, -1);
    's': TryMove(0, 1);
    'a': TryMove(-1, 0);
    'd': TryMove(1, 0);
    'q': TryMove(-1, -1);
    'e': TryMove(1, -1);
    'z': TryMove(-1, 1);
    'c': TryMove(1, 1);
    '>': UseStairs;
    '<': UseStairs;
  end;
end;

procedure TWwViewer.RunScript(const AMoves: string);
var
  i, cx, cy: Integer;
  num: string;
begin
  i := 1;
  while i <= Length(AMoves) do
  begin
    { '@x,y' — указание клетки, тем же путём, каким его делает мышь и
      касание. Нужно, чтобы ходьбу указанием можно было проверить в CI:
      окна там нет, а поведение проверить надо. }
    if AMoves[i] = '@' then
    begin
      Inc(i);
      num := '';
      while (i <= Length(AMoves)) and (AMoves[i] in ['0'..'9']) do
      begin
        num := num + AMoves[i];
        Inc(i);
      end;
      cx := StrToIntDef(num, -1);
      if (i <= Length(AMoves)) and (AMoves[i] = ',') then Inc(i);
      num := '';
      while (i <= Length(AMoves)) and (AMoves[i] in ['0'..'9']) do
      begin
        num := num + AMoves[i];
        Inc(i);
      end;
      cy := StrToIntDef(num, -1);
      if (cx >= 0) and (cy >= 0) then
        WalkTo(cx, cy)
      else
        FStatus := 'в сценарии испорчено указание клетки';
    end
    else
    begin
      HandleKey(AMoves[i]);
      Inc(i);
    end;
  end;
  Render;
end;

{ TWwConsoleViewer }

procedure TWwConsoleViewer.Render;
var
  x, y, ox, oy: Integer;
  row: string;
begin
  ox := FPlayerX - FViewW div 2;
  oy := FPlayerY - FViewH div 2;
  if ox < 0 then ox := 0;
  if oy < 0 then oy := 0;
  if ox > FGrid.W - FViewW then ox := FGrid.W - FViewW;
  if oy > FGrid.H - FViewH then oy := FGrid.H - FViewH;
  if ox < 0 then ox := 0;
  if oy < 0 then oy := 0;

  for y := oy to oy + FViewH - 1 do
  begin
    if y >= FGrid.H then Break;
    row := '';
    for x := ox to ox + FViewW - 1 do
    begin
      if x >= FGrid.W then Break;
      if (x = FPlayerX) and (y = FPlayerY) then
        row := row + '@'
      else
        row := row + GlyphFor(FGrid.CodeAt(x, y));
    end;
    Writeln(row);
  end;
  Writeln(FStatus, '   [WASD/QEZC — ходьба, > и < — лестницы, Esc — выход]');
end;

procedure TWwConsoleViewer.Run;
var
  k: Char;
begin
  repeat
    ClrScr;
    Render;
    k := ReadKey;
    if k = #0 then
    begin
      k := ReadKey;
      case k of
        #72: HandleKey('w');
        #80: HandleKey('s');
        #75: HandleKey('a');
        #77: HandleKey('d');
      end;
    end
    else if k <> #27 then
      HandleKey(k);
  until k = #27;
end;

{$IFDEF USE_BLT}
{ TWwBltViewer }

function TWwBltViewer.ColorFor(ACode: Byte): string;
begin
  case ACode of
    WW_WALL: Result := 'dark gray';
    WW_ROOM: Result := 'light gray';
    WW_COR_MINOR: Result := 'darker orange';
    WW_COR_SECOND: Result := 'orange';
    WW_COR_MAIN: Result := 'yellow';
    WW_JUNCTION: Result := 'cyan';
    WW_FORK: Result := 'light green';
    WW_STAIR_UP: Result := 'white';
    WW_STAIR_DOWN: Result := 'white';
  else
    Result := 'darkest gray';
  end;
end;

procedure TWwBltViewer.ViewOrigin(out AOX, AOY: Integer);
begin
  AOX := FPlayerX - FViewW div 2;
  AOY := FPlayerY - FViewH div 2;
  if AOX < 0 then AOX := 0;
  if AOY < 0 then AOY := 0;
  if AOX > FGrid.W - FViewW then AOX := FGrid.W - FViewW;
  if AOY > FGrid.H - FViewH then AOY := FGrid.H - FViewH;
  if AOX < 0 then AOX := 0;
  if AOY < 0 then AOY := 0;
end;

procedure TWwBltViewer.HandlePointer;
var
  ox, oy, cx, cy: Integer;
begin
  { terminal_state отдаёт клетку, а не пиксель, — пересчитывать нечего.
    На Android касание придёт этим же событием (bearlibterminal#2), поэтому
    отдельной ветки для него здесь не будет и быть не должно. }
  ViewOrigin(ox, oy);
  cx := terminal_state(TK_MOUSE_X);
  cy := terminal_state(TK_MOUSE_Y);

  { Ниже поля — строка состояния и подсказка, туда указывать бессмысленно. }
  if (cy < 0) or (cy >= FViewH) or (cx < 0) or (cx >= FViewW) then
  begin
    FStatus := 'указано мимо карты';
    Exit;
  end;

  WalkTo(ox + cx, oy + cy);
end;

procedure TWwBltViewer.Render;
var
  x, y, ox, oy: Integer;
begin
  terminal_clear;
  ViewOrigin(ox, oy);

  for y := 0 to FViewH - 1 do
    for x := 0 to FViewW - 1 do
    begin
      terminal_color(ColorFor(FGrid.CodeAt(ox + x, oy + y)));
      terminal_put(x, y, Ord(GlyphFor(FGrid.CodeAt(ox + x, oy + y))));
    end;
  terminal_color('light green');
  terminal_put(FPlayerX - ox, FPlayerY - oy, Ord('@'));
  terminal_color('white');
  terminal_print(0, FViewH + 1, AnsiString(FStatus));
  terminal_print(0, FViewH + 2,
    AnsiString('щелчок — идти в клетку, WASD/QEZC — по шагам, > и < — лестницы, Esc — выход'));
  terminal_refresh;
end;

function TWwBltViewer.Step: Boolean;
var
  key: Integer;
begin
  Result := True;

  { Разбираем только то, что уже пришло. terminal_read ждёт события, и в
    покадровом режиме это означало бы остановку до первого касания. }
  while terminal_has_input do
  begin
    key := terminal_read;
    case key of
      TK_W, TK_UP: HandleKey('w');
      TK_S, TK_DOWN: HandleKey('s');
      TK_A, TK_LEFT: HandleKey('a');
      TK_D, TK_RIGHT: HandleKey('d');
      TK_Q: HandleKey('q');
      TK_E: HandleKey('e');
      TK_Z: HandleKey('z');
      TK_C: HandleKey('c');
      TK_PERIOD: UseStairs;
      TK_COMMA: UseStairs;
      TK_MOUSE_LEFT: HandlePointer;
      TK_ESCAPE, TK_CLOSE: Result := False;
    end;
  end;

  Render;
end;

procedure TWwBltViewer.Run;
var
  key: Integer;
begin
  terminal_open;
  terminal_set(AnsiString(Format('window: size=%dx%d, title=''wworld''; font: default',
    [FViewW, FViewH + 3])));
  { Без этого terminal_read не отдаёт щелчки вовсе: по умолчанию в очередь
    попадают только клавиши. }
  terminal_set(AnsiString('input: filter=[keyboard, mouse]'));
  repeat
    Render;
    key := terminal_read;
    case key of
      TK_W, TK_UP: HandleKey('w');
      TK_S, TK_DOWN: HandleKey('s');
      TK_A, TK_LEFT: HandleKey('a');
      TK_D, TK_RIGHT: HandleKey('d');
      TK_Q: HandleKey('q');
      TK_E: HandleKey('e');
      TK_Z: HandleKey('z');
      TK_C: HandleKey('c');
      TK_PERIOD: UseStairs;
      TK_COMMA: UseStairs;
      TK_MOUSE_LEFT: HandlePointer;
    end;
  until (key = TK_ESCAPE) or (key = TK_CLOSE);
  terminal_close;
end;
{$ENDIF}

end.
