object dlgHelpViewer: TdlgHelpViewer
  Left = 0
  Top = 0
  Margins.Left = 6
  Margins.Top = 6
  Margins.Right = 6
  Margins.Bottom = 6
  Caption = 'Help'
  ClientHeight = 800
  ClientWidth = 900
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -24
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poMainFormCenter
  PixelsPerInch = 192
  TextHeight = 32
  object pnlContent: TRzPanel
    Left = 0
    Top = 0
    Width = 900
    Height = 740
    Margins.Left = 6
    Margins.Top = 6
    Margins.Right = 6
    Margins.Bottom = 6
    Align = alClient
    BorderOuter = fsNone
    TabOrder = 0
  end
  object pnlBottom: TRzPanel
    Left = 0
    Top = 740
    Width = 900
    Height = 60
    Margins.Left = 6
    Margins.Top = 6
    Margins.Right = 6
    Margins.Bottom = 6
    Align = alBottom
    BorderOuter = fsNone
    TabOrder = 1
    object btnClose: TRzButton
      Left = 770
      Top = 8
      Width = 120
      Height = 44
      Caption = 'Close'
      ModalResult = 8
      TabOrder = 0
      OnClick = btnCloseClick
    end
  end
end
