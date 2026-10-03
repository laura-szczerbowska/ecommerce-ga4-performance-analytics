# Analiza Efektywności Produktowej i Konwersji GA4: Macierz Asortymentowa & Silnik Rekomendacji (Python | SQL | Power BI)



Kompletny moduł analityczny e-commerce łączący przetwarzanie danych w **Pythonie (Pandas)**, modelowanie w **SQL (PostgreSQL)** oraz wdrożenie interaktywnego, 2-stronicowego raportu decyzyjnego w **Power BI**. Projekt opiera się na rzeczywistych danych komercyjnych ze sklepu internetowego i rozwiązuje problem nieefektywnej alokacji budżetów reklamowych oraz diagnozy konwersji asortymentu w Google Analytics 4.


> **Pochodzenie danych i anonimizacja:**  
> Projekt został zrealizowany na bazie rzeczywistych danych produkcyjnych z działającego sklepu e-commerce. W celu ochrony tajemnicy handlowej zbiór został poddany pełnej **anonimizacji**: nazwy marek, produktów, kampanii oraz wartości metryk zostały przekształcone przy zachowaniu oryginalnych relacji, korelacji, dynamiki konwersji i zachowań użytkowników.

---

<!-- MIEJSCE NA GIF / PREZENTACJĘ WIDEO (BARDZO POLECANE DLA JUNIORA) -->
<!-- Nagraj krótki 10-15s GIF (np. narzędziem ScreenToGif) pokazujący najechanie na bąbelek (tooltip z lejkiem), kliknięcie segmentu i przejście do strony 2 -->
<!-- ![Interaktywny Dashboard Demo](docs/dashboard_demo.gif) -->

---

## 1. Problem Biznesowy

Sklepy e-commerce inwestujące w zróżnicowane źródła ruchu (Google Ads Search, PMax, Ceneo/Referral, ruch organiczny) często przepalają budżety przez brak granularnej analizy na styku: **produkt - kampania - mikrokonwersja**:
* **Przepalanie budżetu na ruch o niskiej intencji:** Kampanie płatne kierują tysiące użytkowników na produkty, które generują odsłony, lecz nie konwertują (niski CR, wysoki koszt pozyskania).
* **Niedoszacowany asortyment o wysokiej konwersji:** Produkty o naturalnie wysokim popycie i silnej intencji zakupowej często nie otrzymują odpowiedniego wsparcia budżetowego z powodu braku widoczności w zagregowanych raportach GA4.
* **Brak diagnostyki wąskich gardeł w lejku:** Tradycyjna analityka rzadko wskazuje, na którym dokładnie etapie odpada klient: czy problemem jest karta produktu i oferta (Views $\to$ Cart Add), czy bariery w procesie zakupowym (Cart Add $\to$ Purchase).

**Cel projektu:** Budowa zautomatyzowanego potoku danych, który kategoryzuje produkty w macierzy efektywności (*Traffic vs. Conversion Matrix*), wizualizuje mikro-lejki zakupowe per SKU i generuje gotowe, operacyjne rekomendacje marketingowe.


<br>



## 2. Architektura i Przepływ Danych

```text
Surowe eksporty GA4 (.csv: kampanie + kategorie)
       │
       ▼
1. Skrypt Python (Pandas) - etl_pipeline.py
   ├── Obsługa kodowania UTF-8-sig i pomijanie błędnych linii
   ├── Audyt jakości: kontrola typów, braków (isna), duplikatów i statystyk
   └── Normalizacja schematu do spójnych kolumn analitycznych
       │
       ▼
2. Warstwa Modelowania i Logiki Biznesowej SQL - widok products_analysis
   ├── Złączenie LEFT JOIN z pre-agregacją kategorii (eliminacja iloczynu kartezjańskiego)
   ├── Kategoryzacja ruchu: Paid Marketing vs. Free source
   ├── Odcięcie szumu statystycznego: HAVING SUM(items_viewed) >= 10
   ├── Autorska metryka: Volume Efficiency Score + flaga Cart Intent
   └── Window Functions: DENSE_RANK() globalnie, w kategorii i w kampanii
       │
       ▼
3. Raport Decyzyjny Power BI
   ├── Strona 1: Executive KPI + Macierz Ruch vs Konwersja (Views vs CR vs Revenue)
   ├── Report-Page Tooltip: Dynamiczny mikro-lejek (Views → Cart adds → Purchases)
   └── Strona 2: Karta produktu, trend sprzedaży w czasie i silnik rekomendacji operacyjnych
```


<br>


## 3. Realizacja Techniczna



1) Python - Czyszczenie i Profilowanie Danych

   
- Odporność na błędy parsowania: Zastosowanie kodowania utf-8-sig oraz parametru on_bad_lines="skip".
- Automatyczny audyt jakości: Walidacja braków danych (isna().sum()), duplikatów (duplicated().sum()) oraz analiza rozkładów zmiennych (describe()).
- Standaryzacja schematu: Przetłumaczenie i ujednolicenie polskich nazw metryk GA4 na format analityczny.



2) SQL - Modelowanie i Logika Biznesowa

   
- Deduplikacja relacji: Pre-agregacja tabeli kategorii za pomocą SELECT DISTINCT w CTE zapobiega powielaniu wierszy i sztucznemu zawyżaniu przychodów w LEFT JOIN.
- Segmentacja źródeł ruchu: Agregacja kampanii do przejrzystych grup biznesowych: Paid Marketing (Google Ads Search, PMax, Ceneo) vs Free source (Organic, Direct).
- Filtr szumu statystycznego: Zastosowanie progu HAVING SUM(items_viewed) >= 10 eliminuje artefakty analityczne (np. 1 wyświetlenie i 1 zakup dające sztuczny CR = 100%).
- Zaawansowane wskaźniki i funkcje okna:
- Volume Efficiency Score: Premiuje produkty generujące realny wolumen transakcji przy wysokim CR:


$$\text{Volume Efficiency Score} = \text{total\_purchased} \times \left( \frac{\text{total\_purchased}}{\text{total\_viewed}} \right)$$


- Flaga cart_intent: Wskaźnik binarny informujący, czy produkt wywołał intencję zakupową (total_cart_adds > 0).
- Hierarchia sprzedaży: Obliczenie pozycji produktu za pomocą DENSE_RANK() OVER (...) osobno w ramach kampanii, kategorii oraz całego katalogu sklepu.


```sql
CREATE OR REPLACE VIEW products_analysis AS

/* join two tables */
WITH base_joined AS (
	SELECT 
	    p.product_name,
	    p.campaign_name,
	    cat.category_name,
	    p.items_viewed,
	    p.items_added_to_cart,
	    p.items_purchased,
	    p.item_revenue
	FROM ga4_products p
	LEFT JOIN (
	    SELECT DISTINCT 
	        product_name, 
	        category_name 
	    FROM ga4_category
	) cat 
	    ON p.product_name = cat.product_name
),



aggregated_products AS(
	SELECT 
	product_name,
	category_name,
	COALESCE(NULLIF(campaign_name, '(not set)'), 'unidentified source') AS campaign_name,
	
	/*compare paid marketing vs free traffic*/
	CASE 
		WHEN campaign_name IN ('Milwaukee-Ogród-Shopping', 'Milwaukee – Narzedzia4you – Search Website traffic-Search-3','PMax | Distar | Sprzedaż | Polska', 'ceneo / referral') 
	    THEN 'Paid Marketing'
		ELSE 'Free source'
	END AS traffic_channel_type,
	
	
	SUM(items_viewed) AS total_viewed,
	SUM(items_added_to_cart) AS total_cart_adds,
	SUM(items_purchased) AS total_purchased,
	SUM(item_revenue) AS total_revenue
	
	FROM base_joined
	
	GROUP BY product_name, category_name, campaign_name, traffic_channel_type
	/*filter out low-traffic items (<10 views) to eliminate statistical noise in conversion rate calculation*/
	HAVING SUM(items_viewed)>=10
)


SELECT 
product_name,
category_name,
campaign_name,
traffic_channel_type,
total_viewed,
total_cart_adds,
total_purchased,
total_revenue,

/*Check if anyone added the item to cart */
CASE 
	WHEN total_cart_adds>0 THEN 1
	ELSE 0
END AS cart_intent,

/*find top products based on sales and conversion, ignoring price*/
ROUND(total_purchased*(total_purchased*1.0/NULLIF(total_viewed,0)),3) AS volume_efficiency_score,

/*rank products by revenue: indside the campaign and overall in the store*/
DENSE_RANK() OVER (PARTITION BY campaign_name ORDER BY total_revenue DESC) AS product_rank_in_campaign,
DENSE_RANK() OVER (PARTITION BY category_name ORDER BY total_revenue DESC) AS product_rank_in_category,
DENSE_RANK() OVER (ORDER BY total_revenue DESC) AS global_revenue_rank

FROM aggregated_products
ORDER BY global_revenue_rank ASC;

```


<br>


## 4. Raport Power BI & Warstwa Wizualna


<br>


### Strona 1: Executive Overview & Macierz Efektywności Produktowej


<br>


<img width="1377" height="773" alt="image" src="https://github.com/user-attachments/assets/54581925-dc93-4893-b3ca-82ea202db40b" />


* **Karty KPI:** Kluczowe wskaźniki sklepu na jednym ekranie: łączny współczynnik konwersji (`CR = 4%`), średnia wartość koszyka (`AOV = 416,21 zł`), przychód (`Revenue = 129,86 tys. zł`) oraz zrealizowane transakcje (`Purchase = 312`).
  
* **Macierz Efektywności Produktowej (*Product Performance Matrix — Traffic vs. CR*):**

  
  * **Oś X:** `views` (Ruch / Wolumen odsłon)
  * **Oś Y:** `CR` (Współczynnik konwersji)
  * **Wielkość bąbelka:** `total_revenue` (Wartość przychodu)
  * **Dynamiczne linie odniesienia** dzielą asortyment na 4 segmenty decyzyjne (wybierane dedykowanym filtrem `Choose matrix segment`):
    * **High Yield (Wysoki ruch, wysoki CR):** Motory przychodowe biznesu; wymagają priorytetu w stanach magazynowych i stabilnego wsparcia reklamowego.
    * **High Potential (Niski ruch, wysoki CR):** Produkty o ponadprzeciętnej konwersji, którym brakuje skali; główni kandydaci do natychmiastowego doskalowania budżetem w Ads (np. dedykowane kampanie PMax).
    * **Requires Optimization (Wysoki ruch, niski CR):** Produkty przepalające budżet; wymagają audytu strony produktowej (CRO), weryfikacji cen na tle konkurencji lub zawężenia słów kluczowych.
    * **Underperforming (Niski ruch, niski CR):** Asortyment nieefektywny; rekomendacja wygaszenia promocji, wyprzedaży lub sprzedaży wiązanej (bundling).
      
* **Zestawienia rynkowe:** Słupkowe analizy przychodu w podziale na kanały marketingowe (dominacja ruchu Referral i Search) oraz kluczowe kategorie (Narzędzia Ogrodowe, Elektronarzędzia).

---

### Dedykowany Tooltip: Mikro-Lejek Zakupowy Produktu (*Report Page Tooltip*)


<br>


<img width="532" height="365" alt="image" src="https://github.com/user-attachments/assets/e702026c-1a52-4be8-aef1-280c1e640462" />


* Najechanie kursorem na dowolny bąbelek na wykresie wywołuje spersonalizowaną podpowiedź wizualną z **pełnym mikro-lejkiem zakupowym** dla wskazanego produktu:


$$\text{Views } (39{,}46\text{ tys.}) \longrightarrow \text{Cart adds } (0{,}32\text{ tys.}) \longrightarrow \text{Purchase } (0{,}31\text{ tys.})$$


* Tooltip natychmiast prezentuje jednostkowy przychód, CR oraz AOV dla wybranego SKU, umożliwiając błyskawiczną identyfikację, czy konwersja spada na etapie koszyka, czy samej oferty.

---

### Strona 2: Karta Produktu, Analiza Trendu i Silnik Rekomendacji


<br>


<img width="1375" height="772" alt="image" src="https://github.com/user-attachments/assets/b74dd08c-a63c-46e4-bf5a-2177281961d0" />


* **Interaktywna nawigacja:** Płynne przejście do widoku szczegółowego przyciskiem **„View product trend”** oraz globalne zerowanie kontekstu filtrowania przyciskiem **„Clear all slicers”**.
* **Trend przychodów w czasie:** Wykres liniowy sprzedaży ujawniający dynamikę popytu, sezonowość oraz reakcję na piki promocyjne.
* **Tabela Rekomendacji Strategicznych (*Strategic Recommendations*):** Silnik regułowy łączący metryki produktu i kampanii z precyzyjnymi akcjami operacyjnymi:
  * **Dla ruchu referral o wysokim CR (43%):** *Maintain ad spend and feature as anchors to boost underperforming campaigns*.
  * **Dla kampanii Search o niskim CR (2%):** *Drive conversion through promotional offers, streamlined checkout, fast delivery, cross-selling, and targeted SEO/keywords*.
  * **Dla źródeł niszowych (wysoki CR, mały wolumen):** *Increase marketing and advertising budget, improve SEO, and explore brand partnerships*.

---

## 5. Kluczowe Wnioski Biznesowe

1. **Efektywność kanału Referral:** Źródła polecające generowały najwyższy współczynnik konwersji i najwyższe AOV przy znacznie niższym jednostkowym koszcie niż generyczne kampanie Search.
2. **Wąskie gardła na etapie finalizacji zamówienia:** Analiza mikro-lejków w tooltipach wykazała, że wybrane produkty generowały wysoki wskaźnik dodania do koszyka (duże zainteresowanie), lecz notowały gwałtowny spadek na etapie płatności — bezpośrednia rekomendacja do weryfikacji progów darmowej dostawy i metod płatności.
3. **Optymalizacja alokacji budżetu Ads:** Identyfikacja produktów w segmencie *Requires Optimization* pozwoliła zarekomendować wykluczenie nieefektywnych fraz kluczowych i przesunięcie uwolnionego budżetu na asortyment z grupy *High Potential*.


<br>


## 6. Stack Technologiczny

**Język & Biblioteki:** Python 3.x, Pandas
**Baza Danych & SQL**: PostgreSQL (CTE, Window Functions, agregacje warunkowe)
**Wizualizacja & BI**: Microsoft Power BI Desktop (DAX, Report-Page Tooltips, Drill-through, Page Interactions)
**Źródło Danych**: Eksporty zdarzeń e-commerce z Google Analytics 4 (GA4)


<br>


## 7. Struktura Repozytorium

```text
ecommerce-ga4-analytics/
├── data/
│   ├── raw/
│   │   ├── products_campaign.csv        # Surowy eksport GA4 (wymiar: kampania)
│   │   └── products_category.csv        # Surowy eksport GA4 (wymiar: kategoria)
│   └── processed/
│       ├── campaign.csv                 # Oczyszczone dane kampanii
│       └── category.csv                 # Oczyszczone dane kategorii
├── sql/
│   └── create_products_analysis_view.sql# Zapytanie tworzące widok analityczny
├── powerbi/
│   └── ecommerce_performance.pbix       # Plik raportu Power BI
├── scripts/
│   └── etl_pipeline.py                  # Skrypt czyszczący i normalizujący w Pythonie
├── docs/
│   ├── executive_matrix.png             # Zrzut ekranu: Dashboard - Strona 1
│   ├── tooltip_funnel.png               # Zrzut ekranu: Dedykowany tooltip z lejkiem
│   └── strategic_actions.png            # Zrzut ekranu: Dashboard - Strona 2
└── README.md
```


<br>


## 8. Instrukcja Uruchomienia

Sklonuj repozytorium:

```bash
git clone https://github.com/twoj-login/ecommerce-ga4-analytics.git
cd ecommerce-ga4-analytics
```

Uruchom potok czyszczenia danych:

```bash
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate
pip install pandas
python scripts/etl_pipeline.py
```

Utwórz widok w bazie danych:

* Zaimportuj wygenerowane pliki campaign.csv i category.csv jako tabele ga4_products i ga4_category.
* Uruchom skrypt sql/create_products_analysis_view.sql.

Uruchom dashboard:

*Otwórz powerbi/ecommerce_performance.pbix w Power BI Desktop.
*Odśwież dane wskazując swoją bazę SQL lub pliki wynikowe z folderu data/processed/


<br>



## 9. Future Roadmap

Potencjalne kierunki dalszego rozwoju modułu i infrastruktury analitycznej:
* **Automatyzacja potoku danych:** Wdrożenie harmonogramowania potoku ETL z bezpośrednim zasilaniem przez BigQuery GA4 Export zamiast ręcznych zrzutów CSV.
* **Integracja danych kosztowych (ROAS):** Podpięcie danych o wydatkach reklamowych z Google Ads API oraz Meta Ads API w celu kalkulacji pełnego wskaźnika zwrotu z nakładów na reklamę (ROAS).
* **Zaawansowane modele predykcyjne:** Rozbudowa o segmentację klientów (RFM) oraz model prognozowania prawdopodobieństwa porzucenia koszyka na podstawie zdarzeń sesyjnych.
* **Integracja stanów magazynowych:** Zestawienie wskaźników popytu i konwersji ze stanami magazynowymi w czasie rzeczywistym, aby automatycznie wstrzymywać kampanie dla produktów o niskim zapasie.


<br>



## 10. Key Takeaways

Projekt łączy analitykę internetową GA4 z inżynierią danych i warstwą Business Intelligence, przekształcając surowe dane o ruchu w gotowe decyzje optymalizacyjne dla asortymentu sklepu:
* **Eliminacja przepalania budżetu:** Zidentyfikowanie produktów w kwadrancie *Requires Optimization* (wysoki ruch, niski CR) pozwala na natychmiastowe obcięcie nieefektywnych fraz kluczowych i zaoszczędzenie budżetu reklamowego.
* **Skalowanie rentowności:** Wykrycie produktów z grupy *High Potential* (niski ruch, wysoki CR) wskazuje asortyment gotowy do zwiększenia wydatków na promocję w kampaniach PMax i Search.
* **Precyzyjna diagnostyka lejka:** Zastosowanie dedykowanego podglądu lejka umożliwia odróżnienie problemów oferty i prezentacji produktu od barier na etapie finalizacji koszyka i kasy.
* **Kompletny warsztat Data Analytics:** Repozytorium demonstruje pełen cykl analityczny: od wczytania i sanityzacji danych w **Pythonie (Pandas)**, przez zaawansowaną logikę relacyjną i funkcje okna w **SQL (PostgreSQL)**, aż po wdrożenie raportu w **Power BI** wyposażonego w mikro-lejki w tooltipach, dwukierunkowe interakcje i silnik rekomendacji operacyjnych.
