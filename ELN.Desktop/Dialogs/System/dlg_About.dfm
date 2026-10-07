object dlgAbout: TdlgAbout
  Left = 0
  Top = 0
  Margins.Left = 2
  Margins.Top = 2
  Margins.Right = 2
  Margins.Bottom = 2
  BorderStyle = bsDialog
  Caption = 'About E-Lab Notebook'
  ClientHeight = 185
  ClientWidth = 340
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poMainFormCenter
  OnCreate = FormCreate
  TextHeight = 15
  object imgIcon: TImage
    Left = 20
    Top = 22
    Width = 48
    Height = 48
    Margins.Left = 2
    Margins.Top = 2
    Margins.Right = 2
    Margins.Bottom = 2
    Stretch = True
  end
  object lblAppName: TLabel
    Left = 85
    Top = 20
    Width = 235
    Height = 28
    Margins.Left = 2
    Margins.Top = 2
    Margins.Right = 2
    Margins.Bottom = 2
    AutoSize = False
    Caption = 'E-Lab Notebook 3'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -19
    Font.Name = 'Segoe UI'
    Font.Style = [fsBold]
    ParentFont = False
  end
  object lblVersion: TLabel
    Left = 85
    Top = 52
    Width = 235
    Height = 18
    Margins.Left = 2
    Margins.Top = 2
    Margins.Right = 2
    Margins.Bottom = 2
    AutoSize = False
    Caption = 'Version'
  end
  object lblCopyright: TLabel
    Left = 85
    Top = 74
    Width = 235
    Height = 18
    Margins.Left = 2
    Margins.Top = 2
    Margins.Right = 2
    Margins.Bottom = 2
    AutoSize = False
    Caption = 'Copyright'
  end
  object bvlSeparator: TBevel
    Left = 15
    Top = 125
    Width = 310
    Height = 2
    Margins.Left = 2
    Margins.Top = 2
    Margins.Right = 2
    Margins.Bottom = 2
    Shape = bsBottomLine
  end
  object btnOK: TButton
    Left = 130
    Top = 143
    Width = 80
    Height = 28
    Margins.Left = 2
    Margins.Top = 2
    Margins.Right = 2
    Margins.Bottom = 2
    Cancel = True
    Caption = 'OK'
    Default = True
    ModalResult = 1
    TabOrder = 0
  end
end
