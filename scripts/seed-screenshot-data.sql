-- seed-screenshot-data.sql
-- Rebuilds the "Hemvo Review" household with rich, realistic demo content for
-- App Store screenshot capture (see HemvoUITests/AppStoreScreenshotUITests.swift).
--
-- Every date is anchored to CURRENT_DATE, so running this immediately before a
-- capture always yields a "this week" meal plan, upcoming bills and a live
-- calendar. It is idempotent — the household's existing content is deleted first.
--
--   supabase db query --linked -f scripts/seed-screenshot-data.sql
--
-- This household also backs the App Review demo login (sales@niemagallery.com),
-- so the reviewer sees the same richer data.

BEGIN;

-- All CURRENT_DATE arithmetic below must resolve in the household's wall-clock
-- zone, not the server's UTC default, or evening events land on the wrong day.
SET LOCAL TIME ZONE 'America/New_York';

-- ── Wipe existing content ────────────────────────────────────────────────────
DELETE FROM grocery_items           WHERE household_id = '2627eaaf-b2ae-4cbd-b89c-11f3ce38255c';
DELETE FROM meals                   WHERE household_id = '2627eaaf-b2ae-4cbd-b89c-11f3ce38255c';
DELETE FROM events                  WHERE household_id = '2627eaaf-b2ae-4cbd-b89c-11f3ce38255c';
DELETE FROM expenses                WHERE household_id = '2627eaaf-b2ae-4cbd-b89c-11f3ce38255c';
DELETE FROM budget_categories       WHERE household_id = '2627eaaf-b2ae-4cbd-b89c-11f3ce38255c';
DELETE FROM maintenance_completions WHERE household_id = '2627eaaf-b2ae-4cbd-b89c-11f3ce38255c';
DELETE FROM house_tasks             WHERE household_id = '2627eaaf-b2ae-4cbd-b89c-11f3ce38255c';

-- A first name reads far better than "Hemvo Reviewer" in the dashboard greeting
-- and the "paid by …" chips; likewise a household name over "Hemvo Review",
-- which is visible on the Household screen.
UPDATE profiles SET full_name = 'Sarah Bennett'
 WHERE id = '3c71d435-b02b-4600-a93c-b11da2a6a666';

UPDATE households SET name = 'The Bennett Home'
 WHERE id = '2627eaaf-b2ae-4cbd-b89c-11f3ce38255c';

-- ── Meals: the current week, Mon..Sun, centred on today ──────────────────────
-- `day` is the legacy ISO weekday (Mon=1); `meal_date` is text 'yyyy-MM-dd'.
-- Dinners carry full ingredient lists — those drive both the Meal Detail screen
-- and the auto-generated grocery list.
INSERT INTO meals (id, household_id, name, day, meal_date, meal_type,
                   ingredients, notes, prep_time_minutes, servings, created_by)
SELECT gen_random_uuid(),
       '2627eaaf-b2ae-4cbd-b89c-11f3ce38255c',
       m.name,
       EXTRACT(isodow FROM d.dt)::int,
       to_char(d.dt, 'YYYY-MM-DD'),
       m.meal_type,
       m.ingredients,
       m.notes,
       m.prep,
       m.servings,
       '3c71d435-b02b-4600-a93c-b11da2a6a666'
FROM (VALUES
  -- offset from the Monday of the current week
  (0, 'Overnight Oats',              'breakfast', 10, 4,
      'Make it the night before — grab and go.',
      jsonb_build_array(
        jsonb_build_object('id',gen_random_uuid(),'name','Rolled oats','quantity','2','unit','cups','category','Pantry','isChecked',false),
        jsonb_build_object('id',gen_random_uuid(),'name','Greek yogurt','quantity','1','unit','tub','category','Dairy','isChecked',false),
        jsonb_build_object('id',gen_random_uuid(),'name','Honey','quantity','1','unit','jar','category','Pantry','isChecked',false))),
  (0, 'Spaghetti Bolognese',         'dinner',    45, 5,
      'Simmer the sauce low and slow for at least 30 minutes.',
      jsonb_build_array(
        jsonb_build_object('id',gen_random_uuid(),'name','Ground beef','quantity','1','unit','lb','category','Meat & Seafood','isChecked',false),
        jsonb_build_object('id',gen_random_uuid(),'name','Spaghetti','quantity','1','unit','box','category','Pantry','isChecked',false),
        jsonb_build_object('id',gen_random_uuid(),'name','Crushed tomatoes','quantity','2','unit','cans','category','Pantry','isChecked',false),
        jsonb_build_object('id',gen_random_uuid(),'name','Parmesan','quantity','1','unit','wedge','category','Dairy','isChecked',false),
        jsonb_build_object('id',gen_random_uuid(),'name','Yellow onion','quantity','1','unit','','category','Produce','isChecked',false))),
  (1, 'Thai Green Curry',            'dinner',    40, 4,
      'Add the basil off the heat so it stays bright.',
      jsonb_build_array(
        jsonb_build_object('id',gen_random_uuid(),'name','Coconut milk','quantity','2','unit','cans','category','Pantry','isChecked',false),
        jsonb_build_object('id',gen_random_uuid(),'name','Green curry paste','quantity','1','unit','jar','category','Pantry','isChecked',false),
        jsonb_build_object('id',gen_random_uuid(),'name','Chicken thighs','quantity','1.5','unit','lb','category','Meat & Seafood','isChecked',false),
        jsonb_build_object('id',gen_random_uuid(),'name','Thai basil','quantity','1','unit','bunch','category','Produce','isChecked',false),
        jsonb_build_object('id',gen_random_uuid(),'name','Jasmine rice','quantity','1','unit','bag','category','Pantry','isChecked',false))),
  (2, 'Lemon Herb Salmon',           'dinner',    30, 4,
      'Roast at 400°F until it flakes — about 14 minutes.',
      jsonb_build_array(
        jsonb_build_object('id',gen_random_uuid(),'name','Salmon fillets','quantity','4','unit','','category','Meat & Seafood','isChecked',false),
        jsonb_build_object('id',gen_random_uuid(),'name','Lemons','quantity','2','unit','','category','Produce','isChecked',false),
        jsonb_build_object('id',gen_random_uuid(),'name','Fresh dill','quantity','1','unit','bunch','category','Produce','isChecked',false),
        jsonb_build_object('id',gen_random_uuid(),'name','Asparagus','quantity','1','unit','bunch','category','Produce','isChecked',false))),
  (3, 'Greek Yogurt Parfait',        'breakfast', 10, 4, '',
      jsonb_build_array(
        jsonb_build_object('id',gen_random_uuid(),'name','Blueberries','quantity','1','unit','pint','category','Produce','isChecked',false),
        jsonb_build_object('id',gen_random_uuid(),'name','Granola','quantity','1','unit','bag','category','Pantry','isChecked',false))),
  (3, 'Turkey & Avocado Wraps',      'lunch',     15, 4, '',
      jsonb_build_array(
        jsonb_build_object('id',gen_random_uuid(),'name','Sliced turkey','quantity','1','unit','lb','category','Meat & Seafood','isChecked',false),
        jsonb_build_object('id',gen_random_uuid(),'name','Avocados','quantity','3','unit','','category','Produce','isChecked',false),
        jsonb_build_object('id',gen_random_uuid(),'name','Tortillas','quantity','1','unit','pack','category','Bakery','isChecked',false))),
  (3, 'Sheet-Pan Chicken Fajitas',   'dinner',    35, 5,
      'One pan, 20 minutes at 425°F. Warm the tortillas at the end.',
      jsonb_build_array(
        jsonb_build_object('id',gen_random_uuid(),'name','Chicken breast','quantity','2','unit','lb','category','Meat & Seafood','isChecked',false),
        jsonb_build_object('id',gen_random_uuid(),'name','Bell peppers','quantity','3','unit','','category','Produce','isChecked',false),
        jsonb_build_object('id',gen_random_uuid(),'name','Red onion','quantity','1','unit','','category','Produce','isChecked',false),
        jsonb_build_object('id',gen_random_uuid(),'name','Lime','quantity','2','unit','','category','Produce','isChecked',false),
        jsonb_build_object('id',gen_random_uuid(),'name','Sour cream','quantity','1','unit','tub','category','Dairy','isChecked',false))),
  (3, 'Apple Slices & Almond Butter','snack',      5, 4, '',
      jsonb_build_array(
        jsonb_build_object('id',gen_random_uuid(),'name','Apples','quantity','6','unit','','category','Produce','isChecked',false),
        jsonb_build_object('id',gen_random_uuid(),'name','Almond butter','quantity','1','unit','jar','category','Pantry','isChecked',false))),
  (4, 'Margherita Pizza Night',      'dinner',    50, 6,
      'Let the dough come to room temperature for an hour first.',
      jsonb_build_array(
        jsonb_build_object('id',gen_random_uuid(),'name','Pizza dough','quantity','2','unit','balls','category','Bakery','isChecked',false),
        jsonb_build_object('id',gen_random_uuid(),'name','Fresh mozzarella','quantity','2','unit','balls','category','Dairy','isChecked',false),
        jsonb_build_object('id',gen_random_uuid(),'name','Fresh basil','quantity','1','unit','bunch','category','Produce','isChecked',false))),
  (5, 'Blueberry Pancakes',          'breakfast', 30, 4, '',
      jsonb_build_array(
        jsonb_build_object('id',gen_random_uuid(),'name','Buttermilk','quantity','1','unit','qt','category','Dairy','isChecked',false),
        jsonb_build_object('id',gen_random_uuid(),'name','Maple syrup','quantity','1','unit','bottle','category','Pantry','isChecked',false))),
  (5, 'Grilled Steak & Chimichurri', 'dinner',    35, 4,
      'Rest the steak 10 minutes before slicing against the grain.',
      jsonb_build_array(
        jsonb_build_object('id',gen_random_uuid(),'name','Flank steak','quantity','2','unit','lb','category','Meat & Seafood','isChecked',false),
        jsonb_build_object('id',gen_random_uuid(),'name','Flat-leaf parsley','quantity','1','unit','bunch','category','Produce','isChecked',false),
        jsonb_build_object('id',gen_random_uuid(),'name','Garlic','quantity','1','unit','head','category','Produce','isChecked',false))),
  (6, 'Sunday Pot Roast',            'dinner',   180, 6,
      'Low oven, lid on, three hours. Worth the wait.',
      jsonb_build_array(
        jsonb_build_object('id',gen_random_uuid(),'name','Chuck roast','quantity','3','unit','lb','category','Meat & Seafood','isChecked',false),
        jsonb_build_object('id',gen_random_uuid(),'name','Carrots','quantity','1','unit','bag','category','Produce','isChecked',false),
        jsonb_build_object('id',gen_random_uuid(),'name','Yukon potatoes','quantity','2','unit','lb','category','Produce','isChecked',false),
        jsonb_build_object('id',gen_random_uuid(),'name','Beef broth','quantity','2','unit','cartons','category','Pantry','isChecked',false)))
) AS m(offs, name, meal_type, prep, servings, notes, ingredients)
CROSS JOIN LATERAL (
  SELECT (date_trunc('week', CURRENT_DATE)::date + m.offs) AS dt
) AS d;

-- ── Grocery: a few manual staples alongside the meal-generated items ─────────
INSERT INTO grocery_items (id, household_id, name, quantity, unit, category, is_checked, created_by)
VALUES
  (gen_random_uuid(),'2627eaaf-b2ae-4cbd-b89c-11f3ce38255c','Paper towels','2','rolls','Household',false,'3c71d435-b02b-4600-a93c-b11da2a6a666'),
  (gen_random_uuid(),'2627eaaf-b2ae-4cbd-b89c-11f3ce38255c','Dish soap','1','','Household',false,'3c71d435-b02b-4600-a93c-b11da2a6a666'),
  (gen_random_uuid(),'2627eaaf-b2ae-4cbd-b89c-11f3ce38255c','Coffee beans','1','bag','Beverages',false,'3c71d435-b02b-4600-a93c-b11da2a6a666'),
  (gen_random_uuid(),'2627eaaf-b2ae-4cbd-b89c-11f3ce38255c','Orange juice','1','carton','Beverages',true,'3c71d435-b02b-4600-a93c-b11da2a6a666'),
  (gen_random_uuid(),'2627eaaf-b2ae-4cbd-b89c-11f3ce38255c','Eggs','1','dozen','Dairy',true,'3c71d435-b02b-4600-a93c-b11da2a6a666');

-- ── Calendar: today through next week, colour-coded by category ──────────────
INSERT INTO events (id, household_id, title, date, end_date, is_all_day, notes,
                    category, color_hex, repeat_rule, scope, location, created_by)
SELECT gen_random_uuid(),
       '2627eaaf-b2ae-4cbd-b89c-11f3ce38255c',
       e.title,
       (CURRENT_DATE + e.offs)::timestamp + e.at,
       (CURRENT_DATE + e.offs)::timestamp + e.at + interval '1 hour',
       e.all_day,
       '',
       e.category,
       e.color_hex,
       'Never',
       'Household',
       e.location,
       '3c71d435-b02b-4600-a93c-b11da2a6a666'
FROM (VALUES
  (0, interval '09:30', 'Dentist — Maya',            'Medical', '#F44336', false, 'Bright Smile Dental'),
  (0, interval '17:30', 'Soccer Practice',           'Sports',  '#E53935', false, 'Riverside Field'),
  (0, interval '20:00', 'Family Movie Night',        'Family',  '#9C27B0', false, ''),
  (1, interval '16:00', 'Parent-Teacher Conference', 'School',  '#2196F3', false, 'Lincoln Elementary'),
  (2, interval '09:00', 'Farmers Market',            'Errand',  '#795548', false, 'Town Square'),
  (2, interval '19:00', 'Dinner with the Chens',     'Social',  '#00BCD4', false, ''),
  (3, interval '00:00', 'Grandma''s Birthday',       'Family',  '#9C27B0', true,  ''),
  (4, interval '09:00', 'Team Offsite',              'Work',    '#FF9800', false, ''),
  (5, interval '16:30', 'Piano Lesson',              'School',  '#2196F3', false, ''),
  (6, interval '11:00', 'Annual Check-up',           'Medical', '#F44336', false, 'Dr. Alvarez'),
  (8, interval '00:00', 'Camping Trip',              'Family',  '#9C27B0', true,  'Pine Ridge'),
  -- A little history, so the month grid does not read as an empty page with one
  -- busy week stuck to the bottom of it.
  (-15, interval '18:30', 'Book Club',               'Social',  '#00BCD4', false, ''),
  (-12, interval '08:00', 'Car Service',             'Errand',  '#795548', false, 'Miller Auto'),
  (-9,  interval '19:00', 'Swim Meet',               'Sports',  '#E53935', false, 'Aquatic Centre'),
  (-6,  interval '12:30', 'Lunch with Dad',          'Family',  '#9C27B0', false, '')
) AS e(offs, at, title, category, color_hex, all_day, location);

-- ── Budget: monthly total, category limits, bills and paid expenses ──────────
-- Sized so the committed total lands near 40% of the bar — a budget that reads as
-- in use, rather than the near-empty sliver a large figure produces.
INSERT INTO budget_settings (household_id, monthly_income)
VALUES ('2627eaaf-b2ae-4cbd-b89c-11f3ce38255c', 2800)
ON CONFLICT (household_id) DO UPDATE SET monthly_income = EXCLUDED.monthly_income;

INSERT INTO budget_categories (id, household_id, name, limit_amount)
VALUES
  (gen_random_uuid(),'2627eaaf-b2ae-4cbd-b89c-11f3ce38255c','Groceries',      600),
  (gen_random_uuid(),'2627eaaf-b2ae-4cbd-b89c-11f3ce38255c','Utilities',      400),
  (gen_random_uuid(),'2627eaaf-b2ae-4cbd-b89c-11f3ce38255c','Insurance',      200),
  (gen_random_uuid(),'2627eaaf-b2ae-4cbd-b89c-11f3ce38255c','Transportation', 200),
  (gen_random_uuid(),'2627eaaf-b2ae-4cbd-b89c-11f3ce38255c','Entertainment',  150),
  (gen_random_uuid(),'2627eaaf-b2ae-4cbd-b89c-11f3ce38255c','Healthcare',     120),
  (gen_random_uuid(),'2627eaaf-b2ae-4cbd-b89c-11f3ce38255c','Dining Out',      75);

-- Unpaid bills, due over the coming days. `series_anchor`/`series_id` stay NULL —
-- these render as ordinary recurring bills.
INSERT INTO expenses (id, household_id, title, amount, category, is_bill, is_recurring,
                      due_date, paid_date, notes, scope, recurrence, created_by, paid_by)
SELECT gen_random_uuid(),
       '2627eaaf-b2ae-4cbd-b89c-11f3ce38255c',
       b.title, b.amount, b.category, true, true,
       (CURRENT_DATE + b.offs)::timestamptz, NULL, '', b.scope, b.recurrence,
       '3c71d435-b02b-4600-a93c-b11da2a6a666', NULL
FROM (VALUES
  (1,  'Phone Plan',    95.00,  'Utilities',     'household', 'monthly'),
  (2,  'Electric Bill', 118.40, 'Utilities',     'household', 'monthly'),
  (4,  'Internet',      79.99,  'Utilities',     'household', 'monthly'),
  (5,  'Gym Membership', 45.00, 'Other',         'personal',  'monthly'),
  (7,  'Car Insurance', 142.00, 'Insurance',     'household', 'monthly')
) AS b(offs, title, amount, category, scope, recurrence);

-- Rent, due the first of next month.
INSERT INTO expenses (id, household_id, title, amount, category, is_bill, is_recurring,
                      due_date, paid_date, notes, scope, recurrence, created_by, paid_by)
VALUES (gen_random_uuid(),'2627eaaf-b2ae-4cbd-b89c-11f3ce38255c','Rent',1850.00,'Mortgage / Rent',
        true, true, (date_trunc('month', CURRENT_DATE) + interval '1 month')::timestamptz,
        NULL, '', 'household', 'monthly', '3c71d435-b02b-4600-a93c-b11da2a6a666', NULL);

-- Paid expenses, placed inside the current month so category spend adds up.
INSERT INTO expenses (id, household_id, title, amount, category, is_bill, is_recurring,
                      due_date, paid_date, notes, scope, recurrence, created_by, paid_by)
SELECT gen_random_uuid(),
       '2627eaaf-b2ae-4cbd-b89c-11f3ce38255c',
       p.title, p.amount, p.category, false, false,
       d.dt, d.dt, '', p.scope, NULL,
       '3c71d435-b02b-4600-a93c-b11da2a6a666',
       '3c71d435-b02b-4600-a93c-b11da2a6a666'
FROM (VALUES
  (2, 'Weekly Groceries',   142.60, 'Groceries',      'household'),
  (5, 'Costco Run',         214.35, 'Groceries',      'household'),
  (1, 'Gas — Shell',         58.20, 'Transportation', 'household'),
  (4, 'Dinner at Luigi''s',  86.50, 'Dining Out',     'household'),
  (3, 'Movie Tickets',       42.00, 'Entertainment',  'household'),
  (6, 'Pharmacy',            34.80, 'Healthcare',     'household'),
  (8, 'Hardware Store',      64.25, 'Other',          'household'),
  (1, 'Coffee Shop',         18.75, 'Dining Out',     'personal'),
  (7, 'Paperback — Book Bar',24.99, 'Entertainment',  'personal')
) AS p(days_ago, title, amount, category, scope)
CROSS JOIN LATERAL (
  -- clamp into the current month so early-in-the-month runs still show spend
  SELECT greatest(date_trunc('month', CURRENT_DATE)::date,
                  CURRENT_DATE - p.days_ago)::timestamptz AS dt
) AS d;

-- ── Fix-It: one overdue, two due soon, the rest healthy ─────────────────────
INSERT INTO house_tasks (id, household_id, title, due_date, is_complete, priority,
                         notes, difficulty, area, frequency, estimated_minutes,
                         task_type, created_by)
SELECT gen_random_uuid(),
       '2627eaaf-b2ae-4cbd-b89c-11f3ce38255c',
       t.title, (CURRENT_DATE + t.offs)::timestamptz, false, t.priority, '',
       t.difficulty, t.area, t.frequency, t.minutes, 'maintenance',
       '3c71d435-b02b-4600-a93c-b11da2a6a666'
FROM (VALUES
  (-4, 'Clean Gutters',        'Yard',     'Quarterly', 45, 'Medium', 'high'),
  ( 3, 'Replace HVAC Filter',  'HVAC',     'Monthly',   15, 'Easy',   'medium'),
  ( 5, 'Descale Coffee Maker', 'Kitchen',  'Monthly',   20, 'Easy',   'low'),
  ( 9, 'Mow the Lawn',         'Yard',     'Weekly',    45, 'Medium', 'medium'),
  (13, 'Deep Clean Bathroom',  'Bathroom', 'Bi-Weekly', 60, 'Medium', 'low'),
  (16, 'Test Smoke Alarms',    'General',  'Monthly',   10, 'Easy',   'medium'),
  (26, 'Change Water Filter',  'Kitchen',  'Quarterly', 15, 'Easy',   'low'),
  (51, 'Garage Tune-Up',       'Garage',   'Annually',  90, 'Hard',   'low')
) AS t(offs, title, area, frequency, minutes, difficulty, priority);

-- Completed history — fills the "Completed" counter and the History sheet.
INSERT INTO maintenance_completions (id, household_id, task_id, completed_by, completed_date,
                                     due_date_at_completion, title, area, frequency,
                                     estimated_minutes, notes)
SELECT gen_random_uuid(),
       '2627eaaf-b2ae-4cbd-b89c-11f3ce38255c',
       NULL,
       '3c71d435-b02b-4600-a93c-b11da2a6a666',
       (CURRENT_DATE - c.days_ago)::timestamptz,
       (CURRENT_DATE - c.days_ago)::timestamptz,
       c.title, c.area, c.frequency, c.minutes, ''
FROM (VALUES
  ( 3, 'Mow the Lawn',      'Yard',    'Weekly',    45),
  ( 7, 'Test Smoke Alarms', 'General', 'Monthly',   10),
  (12, 'Clean Dryer Vent',  'General', 'Quarterly', 30),
  (18, 'Replace HVAC Filter','HVAC',   'Monthly',   15)
) AS c(days_ago, title, area, frequency, minutes);

COMMIT;
