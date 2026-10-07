object frmEditorBase: TfrmEditorBase
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'frmEditorBase'
  ClientHeight = 365
  ClientWidth = 536
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poMainFormCenter
  TextHeight = 15
  object RzPanel1: TRzPanel
    AlignWithMargins = True
    Left = 3
    Top = 3
    Width = 530
    Height = 312
    Align = alClient
    BorderOuter = fsFlatRounded
    TabOrder = 0
    Transparent = True
    Color = clBtnFace
    object DBGrid1: TDBGrid
      AlignWithMargins = True
      Left = 5
      Top = 187
      Width = 520
      Height = 120
      Align = alBottom
      DataSource = DataSource
      TabOrder = 0
      TitleFont.Charset = DEFAULT_CHARSET
      TitleFont.Color = clWindowText
      TitleFont.Height = -12
      TitleFont.Name = 'Segoe UI'
      TitleFont.Style = []
    end
    object RzDBNavigator1: TRzDBNavigator
      Left = 275
      Top = 156
      Width = 240
      Height = 25
      DataSource = DataSource
      BorderOuter = fsNone
      Color = clBtnFace
      TabOrder = 1
    end
  end
  object RzPanel2: TRzPanel
    AlignWithMargins = True
    Left = 3
    Top = 321
    Width = 530
    Height = 41
    Align = alBottom
    BorderOuter = fsFlatRounded
    TabOrder = 1
    Transparent = True
    Color = clBtnFace
    object btnSave: TBitBtn
      Left = 440
      Top = 8
      Width = 75
      Height = 25
      Hint = 'Close'
      Kind = bkClose
      NumGlyphs = 2
      ParentShowHint = False
      ShowHint = True
      TabOrder = 0
    end
    object btnLoadCSV: TBitBtn
      Left = 8
      Top = 8
      Width = 75
      Height = 25
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Caption = 'Load CSV'
      TabOrder = 1
      OnClick = btnLoadCSVClick
    end
  end
  object DataSource: TDataSource
    Left = 475
    Top = 19
  end
  object dlgOpenCSV: TOpenDialog
    Filter = 'CSV files (*.csv)|*.csv|All files (*.*)|*.*'
    Left = 545
    Top = 19
  end
end
