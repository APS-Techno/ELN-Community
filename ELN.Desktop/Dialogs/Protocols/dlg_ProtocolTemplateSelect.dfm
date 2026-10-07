object dlgTemplateSelect: TdlgTemplateSelect
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'Select Template'
  ClientHeight = 375
  ClientWidth = 495
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
    AlignWithMargins = True
    Left = 3
    Top = 331
    Width = 489
    Height = 41
    Align = alBottom
    BorderOuter = fsFlatRounded
    TabOrder = 0
    Color = clBtnFace
    ExplicitTop = 276
    ExplicitWidth = 379
    object btnOK: TRzBitBtn
      Left = 406
      Top = 8
      ModalResult = 1
      Caption = 'OK'
      TabOrder = 0
    end
    object btnCancel: TRzBitBtn
      Left = 8
      Top = 8
      ModalResult = 2
      Caption = 'Cancel'
      TabOrder = 1
    end
  end
  object pnlMain: TRzPanel
    AlignWithMargins = True
    Left = 3
    Top = 3
    Width = 489
    Height = 322
    Align = alClient
    BorderOuter = fsFlatRounded
    TabOrder = 1
    Color = clBtnFace
    ExplicitLeft = 67
    object lblCategories: TRzLabel
      Left = 8
      Top = 6
      Width = 53
      Height = 17
      Caption = 'Category'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -13
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      Transparent = True
    end
    object lblTemplates: TRzLabel
      Left = 248
      Top = 6
      Width = 53
      Height = 17
      Caption = 'Template'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -13
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      Transparent = True
    end
    object lblDescCaption: TRzLabel
      Left = 8
      Top = 292
      Width = 69
      Height = 17
      Caption = 'Description:'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -13
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      Transparent = True
    end
    object lblDescription: TRzLabel
      Left = 8
      Top = 238
      Width = 368
      Height = 20
      AutoSize = False
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = []
      ParentFont = False
      Transparent = True
      WordWrap = True
    end
    object lbCategories: TRzListBox
      Left = 9
      Top = 24
      Width = 220
      Height = 262
      ItemHeight = 15
      TabOrder = 0
      OnClick = lbCategoriesClick
    end
    object lbTemplates: TRzListBox
      Left = 235
      Top = 24
      Width = 246
      Height = 262
      ItemHeight = 15
      TabOrder = 1
      OnClick = lbTemplatesClick
      OnDblClick = lbTemplatesDblClick
    end
  end
end
