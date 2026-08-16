library wwandroid;
{ Игра как библиотека, а не как программа.

  На Android исполняемых файлов приложение не запускает: система загружает
  общую библиотеку и зовёт из неё. Поэтому та же ходилка, что на настольных
  платформах собирается программой wwwalk, здесь собирается библиотекой с
  точкой входа.

  Кадром управляет связка на C++ — она держит поверхность и решает, чем гнать
  цикл: своим потоком или таймером деятельности, когда потока не досталось.
  Отсюда wworld_frame: один кадр за вызов, без собственного цикла внутри.
  Блокирующий Run из TWwViewer здесь не годится именно поэтому.

  Терминал открывает и закрывает связка: он один на приложение, и открывать
  его с двух сторон было бы верным способом получить два разных состояния.

  Сборка:
    fpc -dUSE_BLT -Tandroid -Paarch64 -Fusrc/dungeon ... src/android/wwandroid.pas }

{$MODE OBJFPC}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Math, SysUtils, wwCore, wwGrid, wwPath, wwSource, wwViewer, BearLibTerminal;

var
  { Источник отдельной переменной не держим нарочно: просмотрщик забирает его
    себе и освобождает в своём разрушителе (TWwViewer.Destroy). Держать вторую
    ссылку и освобождать её самому — двойное освобождение, на котором проба и
    падала. }
  GViewer: TWwBltViewer = nil;
  GLastError: AnsiString = '';

{ Открыть подземелье из выгрузки CSV, лежащей по указанному пути.

  Каталог передаёт приложение: ресурсы в APK — не файлы, и деятельность
  раскладывает их в своё хранилище, прежде чем звать сюда.

  Позже здесь появится и второй источник — граф JSON с генерацией на Renjin
  (#6); подпись менять не придётся, различие остаётся внутри. }
function wworld_open(ADir: PAnsiChar): LongBool; cdecl;
begin
  Result := False;
  GLastError := '';
  try
    if GViewer <> nil then
    begin
      GLastError := 'подземелье уже открыто';
      Exit;
    end;

    GViewer := TWwBltViewer.Create(TWwCsvSource.Create(AnsiString(ADir)));
    GViewer.Render;
    Result := True;
  except
    on E: Exception do
    begin
      GLastError := E.Message;
      FreeAndNil(GViewer);
    end;
  end;
end;

{ Причина последней неудачи, для журнала приложения. }
function wworld_last_error: PAnsiChar; cdecl;
begin
  Result := PAnsiChar(GLastError);
end;

{ Один кадр: разобрать накопившийся ввод и перерисовать.

  Возвращает False, когда игра просит выхода, — приложению это знак закрыть
  терминал, а не признак ошибки. }
function wworld_frame: LongBool; cdecl;
begin
  Result := True;
  if GViewer = nil then
  begin
    Result := False;
    Exit;
  end;

  try
    Result := GViewer.Step;
  except
    on E: Exception do
    begin
      GLastError := E.Message;
      terminal_log(TK_LOG_ERROR, 'кадр не удался: ' + E.Message);
      Result := False;
    end;
  end;
end;

procedure wworld_close; cdecl;
begin
  FreeAndNil(GViewer);
end;

exports
  wworld_open,
  wworld_frame,
  wworld_close,
  wworld_last_error;

begin
  { Маска исключений сопроцессора выставляется в привязке BearLibTerminal
    (см. bearlibterminal#9), здесь повторять не нужно. }
end.
