object dlgFileEdit: TdlgFileEdit
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'Edit File'
  ClientHeight = 200
  ClientWidth = 395
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  Position = poMainFormCenter
  TextHeight = 13
  object pnlMain: TRzPanel
    Left = 0
    Top = 0
    Width = 395
    Height = 155
    Align = alClient
    BorderOuter = fsFlatRounded
    TabOrder = 0
    Color = clBtnFace
    object lblTitle: TRzLabel
      Left = 12
      Top = 8
      Width = 24
      Height = 13
      Caption = 'Title:'
    end
    object edtTitle: TRzEdit
      Left = 12
      Top = 24
      Width = 376
      Height = 21
      Text = ''
      TabOrder = 0
    end
    object lblDescription: TRzLabel
      Left = 12
      Top = 54
      Width = 56
      Height = 13
      Caption = 'Description:'
    end
    object edtDescription: TRzMemo
      Left = 12
      Top = 70
      Width = 376
      Height = 75
      ScrollBars = ssVertical
      TabOrder = 1
    end
  end
  object pnlBottom: TRzPanel
    Left = 0
    Top = 155
    Width = 395
    Height = 45
    Align = alBottom
    BorderOuter = fsFlatRounded
    TabOrder = 1
    Color = clBtnFace
    object btnOK: TRzButton
      Left = 237
      Top = 10
      Default = True
      Caption = 'OK'
      TabOrder = 0
      OnClick = btnOKClick
    end
    object btnCancel: TRzButton
      Left = 318
      Top = 10
      Cancel = True
      ModalResult = 2
      Caption = 'Cancel'
      TabOrder = 1
    end
  end
end
