object edProtocols: TedProtocols
  Left = 0
  Top = 0
  Caption = 'Protocol Editor'
  ClientHeight = 450
  ClientWidth = 605
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  Position = poMainFormCenter
  OnCloseQuery = FormCloseQuery
  OnCreate = FormCreate
  OnShow = FormShow
  TextHeight = 13
  object pnlMain: TRzPanel
    Left = 0
    Top = 0
    Width = 605
    Height = 405
    Align = alClient
    BorderOuter = fsFlatRounded
    TabOrder = 0
    Color = clBtnFace
    DesignSize = (
      605
      405)
    object lblTitle: TRzLabel
      Left = 16
      Top = 16
      Width = 24
      Height = 13
      Caption = 'Title:'
    end
    object lblProtocolType: TRzLabel
      Left = 16
      Top = 64
      Width = 70
      Height = 13
      Caption = 'Protocol Type:'
    end
    object lblValidationStatus: TRzLabel
      Left = 212
      Top = 64
      Width = 84
      Height = 13
      Caption = 'Validation Status:'
    end
    object lblTemplate: TRzLabel
      Left = 408
      Top = 64
      Width = 48
      Height = 13
      Caption = 'Template:'
    end
    object edtTitle: TRzEdit
      Left = 16
      Top = 35
      Width = 568
      Height = 21
      Text = ''
      Anchors = [akLeft, akTop, akRight]
      TabOrder = 0
    end
    object cmbProtocolType: TComboBox
      Left = 16
      Top = 84
      Width = 180
      Height = 21
      Style = csDropDownList
      TabOrder = 1
      Items.Strings = (
        'Experiment'
        'Measurement'
        'Analysis'
        'Synthesis'
        'Testing'
        'Other')
    end
    object cmbValidationStatus: TComboBox
      Left = 212
      Top = 84
      Width = 180
      Height = 21
      Style = csDropDownList
      TabOrder = 2
      Items.Strings = (
        'Draft'
        'In Review'
        'Approved'
        'Rejected')
    end
    object cmbTemplate: TComboBox
      Left = 408
      Top = 84
      Width = 176
      Height = 21
      Style = csDropDownList
      Anchors = [akLeft, akTop, akRight]
      TabOrder = 3
      OnChange = cmbTemplateChange
    end
    object pnlFormArea: TRzPanel
      Left = 16
      Top = 116
      Width = 568
      Height = 276
      Anchors = [akLeft, akTop, akRight, akBottom]
      BorderOuter = fsFlatRounded
      TabOrder = 4
      Color = clBtnFace
    end
  end
  object pnlBottom: TRzPanel
    Left = 0
    Top = 405
    Width = 605
    Height = 45
    Align = alBottom
    BorderOuter = fsFlatRounded
    TabOrder = 1
    Color = clBtnFace
    DesignSize = (
      605
      45)
    object btnHistory: TRzButton
      Left = 16
      Top = 10
      Caption = 'History...'
      TabOrder = 0
      Visible = False
      OnClick = btnHistoryClick
    end
    object btnSave: TRzButton
      Left = 419
      Top = 10
      Anchors = [akTop, akRight]
      Caption = 'Save'
      TabOrder = 1
      OnClick = btnSaveClick
    end
    object btnCancel: TBitBtn
      Left = 509
      Top = 10
      Width = 75
      Height = 25
      Anchors = [akTop, akRight]
      Kind = bkCancel
      NumGlyphs = 2
      TabOrder = 2
    end
  end
end
