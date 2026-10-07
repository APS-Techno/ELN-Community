object dlgSign: TdlgSign
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'Sign Item'
  ClientHeight = 380
  ClientWidth = 425
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poMainFormCenter
  OnCreate = FormCreate
  TextHeight = 15
  object pnlBottom: TRzPanel
    Left = 0
    Top = 340
    Width = 425
    Height = 40
    Align = alBottom
    BorderOuter = fsNone
    TabOrder = 0
    Color = clBtnFace
    object btnSign: TRzBitBtn
      Left = 240
      Top = 6
      Width = 80
      Height = 28
      Caption = 'Sign'
      TabOrder = 0
      OnClick = btnSignClick
    end
    object btnCancel: TRzBitBtn
      Left = 328
      Top = 6
      Width = 80
      Height = 28
      ModalResult = 2
      Caption = 'Cancel'
      TabOrder = 1
    end
  end
  object pnlMain: TRzPanel
    Left = 0
    Top = 0
    Width = 425
    Height = 340
    Align = alClient
    BorderOuter = fsNone
    TabOrder = 1
    Color = clBtnFace
    object lblItemTitle: TRzLabel
      Left = 16
      Top = 16
      Width = 53
      Height = 15
      Caption = 'Item Title:'
    end
    object lblMeaning: TRzLabel
      Left = 16
      Top = 68
      Width = 50
      Height = 15
      Caption = 'Meaning:'
    end
    object lblComment: TRzLabel
      Left = 16
      Top = 120
      Width = 57
      Height = 15
      Caption = 'Comment:'
    end
    object lblPassword: TRzLabel
      Left = 16
      Top = 220
      Width = 53
      Height = 15
      Caption = 'Password:'
    end
    object lblWarning: TRzLabel
      Left = 16
      Top = 280
      Width = 388
      Height = 45
      AutoSize = False
      Caption = 
        'WARNING: Signing this item will permanently lock it. No further ' +
        'edits, additions, or deletions will be allowed. This action cann' +
        'ot be undone.'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clRed
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = [fsBold]
      ParentFont = False
      WordWrap = True
    end
    object edItemTitle: TRzEdit
      Left = 16
      Top = 34
      Width = 388
      Height = 23
      Text = ''
      Color = clInfoBk
      FocusColor = clBtnFace
      ReadOnly = True
      TabOrder = 0
    end
    object cbMeaning: TComboBox
      Left = 16
      Top = 86
      Width = 200
      Height = 23
      Style = csDropDownList
      TabOrder = 1
    end
    object edComment: TRzMemo
      Left = 16
      Top = 138
      Width = 388
      Height = 70
      TabOrder = 2
    end
    object edPassword: TRzEdit
      Left = 16
      Top = 238
      Width = 200
      Height = 23
      Text = ''
      PasswordChar = '*'
      TabOrder = 3
    end
  end
end
