object dlgExtractValues: TdlgExtractValues
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'Extract Values from File'
  ClientHeight = 480
  ClientWidth = 720
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poMainFormCenter
  PixelsPerInch = 96
  TextHeight = 15
  object pnlBottom: TRzPanel
    Left = 0
    Top = 440
    Width = 720
    Height = 40
    Align = alBottom
    BorderOuter = fsNone
    TabOrder = 0
    object btnOK: TRzBitBtn
      Left = 540
      Top = 6
      Width = 80
      Height = 28
      Caption = 'OK'
      ModalResult = 1
      TabOrder = 0
    end
    object btnCancel: TRzBitBtn
      Left = 628
      Top = 6
      Width = 80
      Height = 28
      Caption = 'Cancel'
      ModalResult = 2
      TabOrder = 1
    end
  end
  object pnlRight: TRzPanel
    Left = 440
    Top = 0
    Width = 280
    Height = 440
    Align = alRight
    BorderOuter = fsFlatRounded
    TabOrder = 1
    object lblMapping: TRzLabel
      Left = 8
      Top = 8
      Width = 264
      Height = 32
      Align = alNone
      AutoSize = False
      Caption = 'Map to ValueType:'
      WordWrap = True
    end
    object lblCategory: TRzLabel
      Left = 8
      Top = 46
      Width = 264
      Height = 15
      Caption = 'Category:'
    end
    object lbCategory: TListBox
      Left = 8
      Top = 64
      Width = 264
      Height = 104
      TabOrder = 0
      OnClick = lbCategoryClick
    end
    object lblValueType: TRzLabel
      Left = 8
      Top = 174
      Width = 264
      Height = 15
      Caption = 'Value type:'
    end
    object lbValueType: TListBox
      Left = 8
      Top = 192
      Width = 264
      Height = 172
      TabOrder = 1
      OnClick = lbValueTypeClick
    end
    object chkRemember: TCheckBox
      Left = 8
      Top = 372
      Width = 264
      Height = 19
      Caption = 'Remember choices for this reader'
      Checked = True
      ParentShowHint = False
      ShowHint = True
      State = cbChecked
      TabOrder = 2
    end
    object btnNewType: TRzButton
      Left = 8
      Top = 400
      Width = 120
      Height = 28
      Caption = 'New ValueType...'
      TabOrder = 3
      OnClick = btnNewTypeClick
    end
  end
  object pnlClient: TRzPanel
    Left = 0
    Top = 0
    Width = 440
    Height = 440
    Align = alClient
    BorderOuter = fsNone
    TabOrder = 2
    object lblHeader: TRzLabel
      Left = 8
      Top = 4
      Width = 424
      Height = 15
      Caption = 'Select values to extract:'
    end
    object clbValues: TCheckListBox
      Left = 8
      Top = 24
      Width = 424
      Height = 408
      OnClick = clbValuesClick
      TabOrder = 0
    end
  end
end
