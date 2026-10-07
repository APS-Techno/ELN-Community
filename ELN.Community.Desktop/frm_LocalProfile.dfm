object dlgLocalProfile: TdlgLocalProfile
  Left = 0
  Top = 0
  ActiveControl = edtFirstName
  BorderIcons = [biSystemMenu]
  BorderStyle = bsDialog
  Caption = 'Local notebook identity'
  ClientHeight = 434
  ClientWidth = 480
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -13
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poScreenCenter
  OnCloseQuery = FormCloseQuery
  PixelsPerInch = 96
  TextHeight = 17
  object lblIntroduction: TLabel
    Left = 24
    Top = 20
    Width = 432
    Height = 42
    AutoSize = False
    Caption = 'Set the name used for your local notebook records and electronic signatures.'
    WordWrap = True
  end
  object lblFirstName: TLabel
    Left = 24
    Top = 76
    Width = 63
    Height = 17
    Caption = '&First name'
    FocusControl = edtFirstName
  end
  object lblLastName: TLabel
    Left = 248
    Top = 76
    Width = 62
    Height = 17
    Caption = '&Last name'
    FocusControl = edtLastName
  end
  object lblSigningPassword: TLabel
    Left = 24
    Top = 146
    Width = 106
    Height = 17
    Caption = '&Signing password'
    FocusControl = edtSigningPassword
  end
  object lblConfirmation: TLabel
    Left = 24
    Top = 216
    Width = 111
    Height = 17
    Caption = 'Con&firm password'
    FocusControl = edtConfirmation
  end
  object lblPasswordHelp: TLabel
    Left = 24
    Top = 286
    Width = 432
    Height = 56
    AutoSize = False
    Caption = 'This password is for electronic signatures in your local notebook. It is not a team login password. Enter it again when you sign a record.'
    WordWrap = True
  end
  object lblValidation: TLabel
    Left = 24
    Top = 350
    Width = 432
    Height = 26
    AutoSize = False
    Caption = ''
    WordWrap = True
  end
  object edtFirstName: TEdit
    Left = 24
    Top = 100
    Width = 208
    Height = 25
    TabOrder = 0
  end
  object edtLastName: TEdit
    Left = 248
    Top = 100
    Width = 208
    Height = 25
    TabOrder = 1
  end
  object edtSigningPassword: TEdit
    Left = 24
    Top = 170
    Width = 432
    Height = 25
    PasswordChar = '*'
    TabOrder = 2
  end
  object edtConfirmation: TEdit
    Left = 24
    Top = 240
    Width = 432
    Height = 25
    PasswordChar = '*'
    TabOrder = 3
  end
  object btnOK: TButton
    Left = 248
    Top = 386
    Width = 100
    Height = 30
    Caption = 'Create identity'
    Default = True
    ModalResult = 1
    TabOrder = 4
  end
  object btnCancel: TButton
    Left = 356
    Top = 386
    Width = 100
    Height = 30
    Cancel = True
    Caption = 'Cancel'
    ModalResult = 2
    TabOrder = 5
  end
end
