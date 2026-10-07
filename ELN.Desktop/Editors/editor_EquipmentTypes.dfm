inherited edEquipmentTypes: TedEquipmentTypes
  Margins.Left = 2
  Margins.Top = 2
  Margins.Right = 2
  Margins.Bottom = 2
  Caption = 'Equipment Types'
  ClientHeight = 332
  ClientWidth = 283
  ParentFont = True
  ExplicitWidth = 299
  ExplicitHeight = 371
  TextHeight = 15
  inherited RzPanel1: TRzPanel
    Left = 2
    Top = 2
    Width = 279
    Height = 290
    Margins.Left = 2
    Margins.Top = 2
    Margins.Right = 2
    Margins.Bottom = 2
    ExplicitLeft = 2
    ExplicitTop = 2
    ExplicitWidth = 279
    ExplicitHeight = 290
    object Label1: TLabel [0]
      Left = 5
      Top = 12
      Width = 25
      Height = 15
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Caption = 'Type'
    end
    object Label2: TLabel [1]
      Left = 5
      Top = 36
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
      Top = 93
      Width = 271
      Height = 193
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Columns = <
        item
          Expanded = False
          FieldName = 'Type_'
          Title.Caption = 'Type'
          Width = 60
          Visible = True
        end
        item
          Expanded = False
          FieldName = 'Description'
          Width = 125
          Visible = True
        end
        item
          Expanded = False
          FieldName = 'CreatedDate'
          Title.Caption = 'Created Date'
          Width = 55
          Visible = True
        end>
    end
    inherited RzDBNavigator1: TRzDBNavigator
      Left = 5
      Top = 63
      Width = 270
      Height = 26
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Hints.Strings = ()
      ExplicitLeft = 5
      ExplicitTop = 63
      ExplicitWidth = 270
      ExplicitHeight = 26
    end
    object edType: TDBEdit
      Left = 34
      Top = 9
      Width = 239
      Height = 23
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      DataField = 'Type_'
      DataSource = DataSource
      TabOrder = 2
    end
    object edDescription: TDBEdit
      Left = 92
      Top = 36
      Width = 181
      Height = 23
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      DataField = 'Description'
      DataSource = DataSource
      TabOrder = 3
    end
  end
  inherited RzPanel2: TRzPanel
    Left = 2
    Top = 296
    Width = 279
    Height = 34
    Margins.Left = 2
    Margins.Top = 2
    Margins.Right = 2
    Margins.Bottom = 2
    ExplicitLeft = 2
    ExplicitTop = 296
    ExplicitWidth = 279
    ExplicitHeight = 34
    inherited btnSave: TBitBtn
      Left = 213
      Top = 5
      Width = 60
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Anchors = [akRight, akBottom]
      ExplicitLeft = 213
      ExplicitTop = 5
      ExplicitWidth = 60
    end
    inherited btnLoadCSV: TBitBtn
      Left = 5
      Top = 3
      Width = 60
      Margins.Left = 1
      Margins.Top = 1
      Margins.Right = 1
      Margins.Bottom = 1
      ExplicitLeft = 5
      ExplicitTop = 3
      ExplicitWidth = 60
    end
  end
  inherited DataSource: TDataSource
    Left = 339
    Top = 227
  end
end
