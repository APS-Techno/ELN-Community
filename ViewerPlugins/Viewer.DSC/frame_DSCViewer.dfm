object frameDSCViewer: TframeDSCViewer
  Left = 0
  Top = 0
  Width = 1343
  Height = 1013
  TabOrder = 0
  PixelsPerInch = 192
  object Editor: TSynEdit
    AlignWithMargins = True
    Left = 6
    Top = 99
    Width = 1331
    Height = 908
    Margins.Left = 6
    Margins.Top = 6
    Margins.Right = 6
    Margins.Bottom = 6
    Align = alClient
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -32
    Font.Name = 'Courier New'
    Font.Style = []
    Font.Quality = fqClearTypeNatural
    TabOrder = 0
    CodeFolding.ShowCollapsedLine = True
    UseCodeFolding = False
    BookMarkOptions.LeftMargin = 4
    BookMarkOptions.Xoffset = 24
    ExtraLineSpacing = 4
    Gutter.DigitCount = 2
    Gutter.Font.Charset = DEFAULT_CHARSET
    Gutter.Font.Color = clWindowText
    Gutter.Font.Height = -26
    Gutter.Font.Name = 'Courier New'
    Gutter.Font.Style = []
    Gutter.Font.Quality = fqClearTypeNatural
    Gutter.ShowLineNumbers = True
    Gutter.Bands = <
      item
        Kind = gbkMarks
        Width = 13
      end
      item
        Kind = gbkLineNumbers
      end
      item
        Kind = gbkFold
      end
      item
        Kind = gbkTrackChanges
      end
      item
        Kind = gbkMargin
        Width = 3
      end>
    Highlighter = Syn
    Lines.Strings = (
      'var warmupTime 1'
      'start'
      '  warmup warmupTime B Ion Ti '
      'finish')
    ReadOnly = True
    SelectedColor.Alpha = 0.400000005960464500
    ExplicitTop = 224
    ExplicitHeight = 783
  end
  object RzPanel1: TRzPanel
    AlignWithMargins = True
    Left = 6
    Top = 6
    Width = 1331
    Height = 81
    Margins.Left = 6
    Margins.Top = 6
    Margins.Right = 6
    Margins.Bottom = 6
    Align = alTop
    BevelWidth = 2
    BorderOuter = fsFlatRounded
    TabOrder = 1
    ExplicitLeft = 0
    ExplicitTop = 0
    ExplicitWidth = 1343
    object lblTitle: TRzLabel
      Left = 25
      Top = 22
      Width = 91
      Height = 37
      Margins.Left = 6
      Margins.Top = 6
      Margins.Right = 6
      Margins.Bottom = 6
      Caption = 'lblTitle'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -27
      Font.Name = 'Segoe UI'
      Font.Style = [fsBold]
      ParentFont = False
    end
  end
  object Syn: TSynGeneralSyn
    CommentAttri.Foreground = clGreen
    Comments = [csCPPStyle]
    DetectPreprocessor = False
    IdentifierAttri.Foreground = clBlue
    IdentifierChars = '_0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz$'
    KeyWords.Strings = (
      'FINISH'
      'START'
      'VAR')
    NumberAttri.Foreground = clMaroon
    StringAttri.Foreground = clTeal
    StringAttri.Style = [fsItalic]
    SymbolAttri.Foreground = clNavy
    SymbolAttri.Style = [fsItalic]
    StringDelim = sdDoubleQuote
    Left = 497
    Top = 241
  end
end
