inherited edValueTypes: TedValueTypes
  Margins.Left = 2
  Margins.Top = 2
  Margins.Right = 2
  Margins.Bottom = 2
  Caption = 'Value Types'
  ClientHeight = 403
  ClientWidth = 416
  ParentFont = True
  ExplicitWidth = 432
  ExplicitHeight = 442
  TextHeight = 15
  inherited RzPanel1: TRzPanel
    Left = 2
    Top = 2
    Width = 412
    Height = 352
    Margins.Left = 2
    Margins.Top = 2
    Margins.Right = 2
    Margins.Bottom = 2
    ExplicitLeft = 2
    ExplicitTop = 2
    ExplicitWidth = 412
    ExplicitHeight = 282
    object Label1: TLabel [0]
      Left = 28
      Top = 13
      Width = 40
      Height = 15
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Caption = 'Symbol'
    end
    object Label2: TLabel [1]
      Left = 192
      Top = 13
      Width = 23
      Height = 15
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Caption = 'Title'
    end
    object Label3: TLabel [2]
      Left = 37
      Top = 40
      Width = 27
      Height = 15
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Caption = 'Units'
    end
    object Label4: TLabel [3]
      Left = 188
      Top = 41
      Width = 48
      Height = 15
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Caption = 'Category'
    end
    object Label5: TLabel [4]
      Left = 11
      Top = 68
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
      Top = 125
      Width = 404
      Height = 223
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Columns = <
        item
          Alignment = taCenter
          Expanded = False
          FieldName = 'Symbol'
          Width = 59
          Visible = True
        end
        item
          Expanded = False
          FieldName = 'Title'
          Width = 76
          Visible = True
        end
        item
          Alignment = taCenter
          Expanded = False
          FieldName = 'Units'
          Width = 40
          Visible = True
        end
        item
          Expanded = False
          FieldName = 'CatID'
          Title.Caption = 'Category'
          Width = 71
          Visible = True
        end
        item
          Expanded = False
          FieldName = 'Description'
          Width = 100
          Visible = True
        end
        item
          Expanded = False
          FieldName = 'CreatedDate'
          Title.Caption = 'Created'
          Width = 75
          Visible = True
        end>
    end
    inherited RzDBNavigator1: TRzDBNavigator
      Left = 144
      Top = 92
      Width = 260
      Height = 29
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Hints.Strings = ()
      ExplicitLeft = 144
      ExplicitTop = 92
      ExplicitWidth = 260
      ExplicitHeight = 29
    end
    object edSymbol: TDBEdit
      Left = 80
      Top = 10
      Width = 100
      Height = 23
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      DataField = 'Symbol'
      DataSource = DataSource
      TabOrder = 2
    end
    object edTitle: TDBEdit
      Left = 232
      Top = 10
      Width = 170
      Height = 23
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      DataField = 'Title'
      DataSource = DataSource
      TabOrder = 3
    end
    object edUnits: TDBEdit
      Left = 80
      Top = 37
      Width = 100
      Height = 23
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      DataField = 'Units'
      DataSource = DataSource
      TabOrder = 4
    end
    object cbCategory: TComboBox
      Left = 252
      Top = 38
      Width = 150
      Height = 23
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Style = csDropDownList
      TabOrder = 5
      OnChange = cbCategoryChange
    end
    object edDescription: TDBEdit
      Left = 80
      Top = 65
      Width = 322
      Height = 23
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      DataField = 'Description'
      DataSource = DataSource
      TabOrder = 6
    end
    object pnlCategories: TPanel
      Align = alLeft
      Width = 140
      BevelOuter = bvNone
      ParentBackground = True
      TabOrder = 7
      object lblCategoryHdr: TLabel
        Align = alTop
        Height = 20
        Caption = ' Category'
        Layout = tlCenter
      end
      object lbCategories: TListBox
        Align = alClient
        AlignWithMargins = True
        Margins.Left = 4
        Margins.Top = 0
        Margins.Right = 4
        Margins.Bottom = 4
        TabOrder = 0
        OnClick = lbCategoriesClick
      end
      object pnlCatButtons: TPanel
        Align = alBottom
        Height = 28
        BevelOuter = bvNone
        ParentBackground = True
        TabOrder = 1
        object btnCatAdd: TButton
          Left = 4
          Top = 2
          Width = 42
          Height = 24
          Caption = 'Add'
          TabOrder = 0
          OnClick = btnCatAddClick
        end
        object btnCatRename: TButton
          Left = 49
          Top = 2
          Width = 48
          Height = 24
          Caption = 'Rename'
          TabOrder = 1
          OnClick = btnCatRenameClick
        end
        object btnCatMove: TButton
          Left = 100
          Top = 2
          Width = 36
          Height = 24
          Caption = 'Move'
          TabOrder = 2
          OnClick = btnCatMoveClick
        end
      end
    end
    object pnlDetail: TPanel
      Align = alClient
      BevelOuter = bvNone
      ParentBackground = True
      TabOrder = 8
    end
  end
  inherited RzPanel2: TRzPanel
    Left = 2
    Top = 358
    Width = 412
    Height = 43
    Margins.Left = 2
    Margins.Top = 2
    Margins.Right = 2
    Margins.Bottom = 2
    ExplicitLeft = 2
    ExplicitTop = 288
    ExplicitWidth = 412
    ExplicitHeight = 43
    DesignSize = (
      412
      43)
    inherited btnSave: TBitBtn
      Left = 344
      Top = 11
      Width = 60
      Margins.Left = 2
      Margins.Top = 2
      Margins.Right = 2
      Margins.Bottom = 2
      Anchors = [akRight, akBottom]
      ExplicitLeft = 344
      ExplicitTop = 11
      ExplicitWidth = 60
    end
    inherited btnLoadCSV: TBitBtn
      Top = 10
      Width = 60
      Margins.Left = 1
      Margins.Top = 1
      Margins.Right = 1
      Margins.Bottom = 1
      ExplicitTop = 10
      ExplicitWidth = 60
    end
  end
end
