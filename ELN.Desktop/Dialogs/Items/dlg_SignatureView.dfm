object dlgSignatureView: TdlgSignatureView
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'Signature Details'
  ClientHeight = 400
  ClientWidth = 485
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poMainFormCenter
  TextHeight = 15
  object pnlBottom: TRzPanel
    Left = 0
    Top = 360
    Width = 485
    Height = 40
    Align = alBottom
    BorderOuter = fsNone
    TabOrder = 0
    Color = clBtnFace
    object btnVerify: TRzBitBtn
      Left = 280
      Top = 6
      Width = 100
      Height = 28
      Caption = 'Verify Now'
      TabOrder = 0
      OnClick = btnVerifyClick
    end
    object btnClose: TRzBitBtn
      Left = 388
      Top = 6
      Width = 80
      Height = 28
      ModalResult = 2
      Caption = 'Close'
      TabOrder = 1
    end
  end
  object pnlMain: TRzPanel
    Left = 0
    Top = 0
    Width = 485
    Height = 360
    Align = alClient
    BorderOuter = fsNone
    TabOrder = 1
    Color = clBtnFace
    object lblSignedBy: TRzLabel
      Left = 16
      Top = 16
      Width = 55
      Height = 15
      Caption = 'Signed By:'
    end
    object lblDate: TRzLabel
      Left = 16
      Top = 66
      Width = 27
      Height = 15
      Caption = 'Date:'
    end
    object lblMeaning: TRzLabel
      Left = 240
      Top = 66
      Width = 50
      Height = 15
      Caption = 'Meaning:'
    end
    object lblComment: TRzLabel
      Left = 16
      Top = 116
      Width = 57
      Height = 15
      Caption = 'Comment:'
    end
    object lblHash: TRzLabel
      Left = 16
      Top = 206
      Width = 76
      Height = 15
      Caption = 'Content Hash:'
    end
    object lblIntegrity: TRzLabel
      Left = 16
      Top = 260
      Width = 82
      Height = 15
      Caption = 'Integrity Status:'
    end
    object edSignedBy: TRzEdit
      Left = 16
      Top = 34
      Width = 448
      Height = 23
      Text = ''
      Color = clInfoBk
      FocusColor = clBtnFace
      ReadOnly = True
      TabOrder = 0
    end
    object edDate: TRzEdit
      Left = 16
      Top = 84
      Width = 200
      Height = 23
      Text = ''
      Color = clInfoBk
      FocusColor = clBtnFace
      ReadOnly = True
      TabOrder = 1
    end
    object edMeaning: TRzEdit
      Left = 240
      Top = 84
      Width = 224
      Height = 23
      Text = ''
      Color = clInfoBk
      FocusColor = clBtnFace
      ReadOnly = True
      TabOrder = 2
    end
    object edComment: TRzMemo
      Left = 16
      Top = 134
      Width = 448
      Height = 60
      Color = clInfoBk
      ReadOnly = True
      TabOrder = 3
      FocusColor = clBtnFace
    end
    object edHash: TRzEdit
      Left = 16
      Top = 224
      Width = 448
      Height = 23
      Text = ''
      Color = clInfoBk
      FocusColor = clBtnFace
      ReadOnly = True
      TabOrder = 4
    end
    object edIntegrity: TRzEdit
      Left = 16
      Top = 278
      Width = 448
      Height = 23
      Text = ''
      Color = clInfoBk
      FocusColor = clBtnFace
      ReadOnly = True
      TabOrder = 5
    end
  end
end
