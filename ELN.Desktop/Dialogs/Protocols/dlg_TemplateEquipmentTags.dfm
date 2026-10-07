object dlgTemplateEquipmentTags: TdlgTemplateEquipmentTags
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'Equipment tags'
  ClientHeight = 420
  ClientWidth = 600
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  Position = poOwnerFormCenter
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  TextHeight = 13
  object spltMid: TSplitter
    Left = 297
    Top = 0
    Width = 6
    Height = 379
    Align = alLeft
  end
  object pnlLeft: TRzPanel
    Left = 0
    Top = 0
    Width = 297
    Height = 379
    Align = alLeft
    BorderOuter = fsNone
    TabOrder = 0
    object lblTypes: TRzLabel
      Left = 12
      Top = 8
      Width = 80
      Height = 13
      Caption = 'Equipment types'
    end
    object clbTypes: TCheckListBox
      Left = 12
      Top = 28
      Width = 273
      Height = 340
      Anchors = [akLeft, akTop, akRight, akBottom]
      ItemHeight = 13
      TabOrder = 0
      OnClickCheck = clbTypesClickCheck
    end
  end
  object pnlRight: TRzPanel
    Left = 303
    Top = 0
    Width = 297
    Height = 379
    Align = alClient
    BorderOuter = fsNone
    TabOrder = 1
    object lblDevices: TRzLabel
      Left = 12
      Top = 8
      Width = 39
      Height = 13
      Caption = 'Devices'
    end
    object clbDevices: TCheckListBox
      Left = 12
      Top = 28
      Width = 273
      Height = 340
      Anchors = [akLeft, akTop, akRight, akBottom]
      ItemHeight = 13
      TabOrder = 0
    end
  end
  object pnlBottom: TRzPanel
    Left = 0
    Top = 379
    Width = 600
    Height = 41
    Align = alBottom
    BorderOuter = fsNone
    TabOrder = 2
    object btnOK: TRzButton
      Left = 420
      Top = 8
      Width = 75
      Height = 25
      Caption = 'OK'
      Default = True
      ModalResult = 1
      TabOrder = 0
      OnClick = btnOKClick
    end
    object btnCancel: TRzButton
      Left = 510
      Top = 8
      Width = 75
      Height = 25
      Caption = 'Cancel'
      Cancel = True
      ModalResult = 2
      TabOrder = 1
    end
  end
end
