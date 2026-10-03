import pandas as pd

# Terminal display configuration
pd.set_option('display.max_columns', None)
pd.set_option('display.width', 1000)

file_campaign = "products_campaign.csv"
file_category = "products_category.csv"

# Schema mapping GA4 raw export
camp_mapping = {
    'Nazwa': 'product_name',
    'Sesja – kampania': 'campaign_name',
    'Wyświetlone produkty': 'items_viewed',
    'Produkty dodane do koszyka': 'items_added_to_cart',
    'Kupione produkty': 'items_purchased',
    'Przychody z produktu': 'item_revenue'
}

cat_mapping = {
    "Nazwa": "product_name",
    "Kategoria produktu": "category_name",
    "Wyświetlone produkty": "items_viewed",
    "Produkty dodane do koszyka": "items_added_to_cart",
    "Kupione produkty": "items_purchased",
    "Przychody z produktu": "item_revenue",
}

#Loads raw CSV file, performs data integrity checks and logs quality metrics.
def load_and_audit(file_path):
    df = pd.read_csv(file_path, encoding="utf-8-sig", on_bad_lines="skip", sep=",")
    print(f"{df.head(3)}")
    print(f"Dimensions: {df.shape}")
    print(f"Data types: {df.dtypes}")
    print(f"Missing values:{df.isna().sum()}")
    print(f"Duplicate rows count: {df.duplicated().sum()}")
    return df

#Sanitizes records, maps column names, and exports ready-to-load CSV for SQL.
def clean_and_export(df, mapping, output_path):
    df_clean = df.rename(columns=mapping)
    df_clean.to_csv(output_path, index=False, encoding="utf-8-sig")
    print(f"Successfully exported:{output_path}")
    return df_clean

if __name__ == "__main__":
    df_camp_raw = load_and_audit(file_campaign, "products_campaign")
    df_cat_raw = load_and_audit(file_category, "products_category")

    df_camp = clean_and_export(df_camp_raw, camp_mapping, "campaign.csv")
    df_cat = clean_and_export(df_cat_raw, cat_mapping, "category.csv")

