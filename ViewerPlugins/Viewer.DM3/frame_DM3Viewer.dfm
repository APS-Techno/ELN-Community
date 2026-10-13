object frameDM3Viewer: TframeDM3Viewer
  Left = 0
  Top = 0
  Width = 900
  Height = 600
  TabOrder = 0
  object pnlMeta: TPanel
    Left = 680
    Top = 0
    Width = 220
    Height = 574
    Align = alRight
    BevelOuter = bvNone
    TabOrder = 0
    object lblInfo: TLabel
      AlignWithMargins = True
      Left = 8
      Top = 8
      Width = 204
      Height = 558
      Margins.Left = 8
      Margins.Top = 8
      Margins.Right = 8
      Margins.Bottom = 8
      Align = alClient
      AutoSize = False
      Caption = ''
      WordWrap = True
    end
  end
  object ScrollBox: TScrollBox
    Left = 0
    Top = 0
    Width = 680
    Height = 574
    Align = alClient
    TabOrder = 1
    object Image: TImage
      Left = 0
      Top = 0
      Width = 680
      Height = 574
      Align = alClient
      Proportional = True
      Stretch = True
      Center = True
    end
  end
  object Status: TRzStatusBar
    Left = 0
    Top = 574
    Width = 900
    Height = 26
    BorderInner = fsNone
    BorderOuter = fsNone
    TabOrder = 2
    object pnlFile: TRzStatusPane
      Left = 0
      Top = 0
      Width = 300
      Height = 26
      Align = alLeft
      Alignment = taLeftJustify
    end
    object pnlDims: TRzStatusPane
      Left = 300
      Top = 0
      Width = 120
      Height = 26
      Align = alLeft
    end
    object pnlScale: TRzStatusPane
      Left = 420
      Top = 0
      Width = 180
      Height = 26
      Align = alLeft
    end
  end
end
