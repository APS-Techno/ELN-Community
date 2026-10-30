object dlgSearchSetup: TdlgSearchSetup
  Left = 0
  Top = 0
  BorderIcons = [biSystemMenu]
  BorderStyle = bsDialog
  Caption = 'Semantic Search Setup'
  ClientHeight = 372
  ClientWidth = 520
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poOwnerFormCenter
  OnCloseQuery = FormCloseQuery
  TextHeight = 15
  object lblState: TLabel
    Left = 16
    Top = 16
    Width = 488
    Height = 15
    AutoSize = False
    Caption = 'State: Checking...'
  end
  object lblSize: TLabel
    Left = 16
    Top = 40
    Width = 488
    Height = 15
    AutoSize = False
    Caption = 'Download size:'
  end
  object lblFolder: TLabel
    Left = 16
    Top = 64
    Width = 488
    Height = 15
    AutoSize = False
    Caption = 'Target folder:'
    EllipsisPosition = epPathEllipsis
    ShowHint = True
  end
  object lvParts: TListView
    Left = 16
    Top = 88
    Width = 488
    Height = 100
    Columns = <
      item
        Caption = 'Part'
        Width = 195
      end
      item
        Caption = 'Use'
        Width = 65
      end
      item
        Caption = 'License'
        Width = 80
      end
      item
        Caption = 'Size'
        Width = 70
      end
      item
        Caption = 'State'
        Width = 70
      end>
    ReadOnly = True
    RowSelect = True
    TabOrder = 0
    ViewStyle = vsReport
  end
  object lblLicense: TLabel
    Left = 16
    Top = 196
    Width = 488
    Height = 48
    AutoSize = False
    Caption = ' '
    WordWrap = True
  end
  object lblIndex: TLabel
    Left = 16
    Top = 252
    Width = 488
    Height = 15
    AutoSize = False
    Caption = 'Index:'
  end
  object lblFile: TLabel
    Left = 16
    Top = 276
    Width = 488
    Height = 15
    AutoSize = False
    Caption = ' '
    EllipsisPosition = epPathEllipsis
  end
  object barProgress: TProgressBar
    Left = 16
    Top = 296
    Width = 488
    Height = 18
    Max = 1000
    TabOrder = 1
  end
  object btnInstall: TButton
    Left = 16
    Top = 332
    Width = 150
    Height = 25
    Caption = 'Download and Install'
    TabOrder = 2
    OnClick = btnInstallClick
  end
  object btnVerify: TButton
    Left = 172
    Top = 332
    Width = 80
    Height = 25
    Caption = 'Verify'
    TabOrder = 3
    OnClick = btnVerifyClick
  end
  object btnRemove: TButton
    Left = 258
    Top = 332
    Width = 80
    Height = 25
    Caption = 'Remove'
    TabOrder = 4
    OnClick = btnRemoveClick
  end
  object btnClose: TButton
    Left = 424
    Top = 332
    Width = 80
    Height = 25
    Cancel = True
    Caption = 'Close'
    TabOrder = 5
    OnClick = btnCloseClick
  end
  object tmrPoll: TTimer
    Interval = 150
    OnTimer = tmrPollTimer
    Left = 456
    Top = 120
  end
end
