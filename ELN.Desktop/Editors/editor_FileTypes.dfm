inherited edFileTypes: TedFileTypes
  Margins.Left = 2
  Margins.Top = 2
  Margins.Right = 2
  Margins.Bottom = 2
  Caption = 'File Types'
  ClientHeight = 379
  ClientWidth = 495
  ParentFont = True
  ExplicitWidth = 511
  ExplicitHeight = 418
  TextHeight = 15
  inherited RzPanel1: TRzPanel
    Left = 2
    Top = 2
    Width = 491
    Height = 338
    Margins.Left = 2
    Margins.Top = 2
    Margins.Right = 2
    Margins.Bottom = 2
    ExplicitLeft = 2
    ExplicitTop = 2
    ExplicitWidth = 378
    ExplicitHeight = 274
    object Label1: TLabel [0]
      Left = 15
      Top = 13
      Width = 50
      Height = 15
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Caption = 'Extension'
    end
    object Label2: TLabel [1]
      Left = 149
      Top = 13
      Width = 60
      Height = 15
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Caption = 'Description'
    end
    inherited DBGrid1: TDBGrid
      Left = 4
      Top = 69
      Width = 483
      Height = 265
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Columns = <
        item
          Alignment = taCenter
          Expanded = False
          FieldName = 'Ext'
          Title.Caption = 'Extension'
          Width = 74
          Visible = True
        end
        item
          Expanded = False
          FieldName = 'Description'
          ReadOnly = True
          Width = 273
          Visible = True
        end
        item
          Expanded = False
          FieldName = 'CreatedDate'
          Title.Caption = 'Created Date'
          Width = 94
          Visible = True
        end>
    end
    inherited RzDBNavigator1: TRzDBNavigator
      Left = 192
      Top = 37
      Width = 290
      Height = 28
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Hints.Strings = ()
      ExplicitLeft = 192
      ExplicitTop = 37
      ExplicitWidth = 290
      ExplicitHeight = 28
    end
    object DBIcon: TDBImage
      Left = 460
      Top = 10
      Width = 22
      Height = 23
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      DataField = 'Icon'
      DataSource = DataSource
      ReadOnly = True
      TabOrder = 2
    end
    object edExtension: TDBEdit
      Left = 80
      Top = 10
      Width = 57
      Height = 23
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      DataField = 'Ext'
      DataSource = DataSource
      TabOrder = 3
    end
    object edDescription: TDBEdit
      Left = 213
      Top = 10
      Width = 243
      Height = 23
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      DataField = 'Description'
      DataSource = DataSource
      TabOrder = 4
    end
  end
  inherited RzPanel2: TRzPanel
    Left = 2
    Top = 344
    Width = 491
    Height = 33
    Margins.Left = 2
    Margins.Top = 2
    Margins.Right = 2
    Margins.Bottom = 2
    ExplicitLeft = 2
    ExplicitTop = 280
    ExplicitWidth = 378
    ExplicitHeight = 33
    DesignSize = (
      491
      33)
    inherited btnSave: TBitBtn
      Left = 422
      Top = 3
      Width = 60
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Anchors = [akRight, akBottom]
      ExplicitLeft = 309
      ExplicitTop = 3
      ExplicitWidth = 60
    end
    inherited btnLoadCSV: TBitBtn
      Left = 7
      Top = 3
      Width = 60
      Margins.Left = 1
      Margins.Top = 1
      Margins.Right = 1
      Margins.Bottom = 1
      ExplicitLeft = 7
      ExplicitTop = 3
      ExplicitWidth = 60
    end
  end
  inherited DataSource: TDataSource
    Left = 339
    Top = 227
  end
end
