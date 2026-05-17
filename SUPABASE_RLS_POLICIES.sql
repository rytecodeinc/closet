-- Row Level Security (RLS) Policies for Closet App
-- These policies ensure users can only access their own data

-- Enable RLS on all tables
ALTER TABLE items ENABLE ROW LEVEL SECURITY;
ALTER TABLE brands ENABLE ROW LEVEL SECURITY;
ALTER TABLE categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE subcategories ENABLE ROW LEVEL SECURITY;
ALTER TABLE colors ENABLE ROW LEVEL SECURITY;
ALTER TABLE seasons ENABLE ROW LEVEL SECURITY;
ALTER TABLE sizes ENABLE ROW LEVEL SECURITY;
ALTER TABLE tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE collections ENABLE ROW LEVEL SECURITY;
ALTER TABLE wardrobes ENABLE ROW LEVEL SECURITY;
ALTER TABLE outfits ENABLE ROW LEVEL SECURITY;
ALTER TABLE events ENABLE ROW LEVEL SECURITY;
ALTER TABLE item_photos ENABLE ROW LEVEL SECURITY;
ALTER TABLE item_prices ENABLE ROW LEVEL SECURITY;
ALTER TABLE item_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE item_colors ENABLE ROW LEVEL SECURITY;
ALTER TABLE item_seasons ENABLE ROW LEVEL SECURITY;
ALTER TABLE item_tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE item_collections ENABLE ROW LEVEL SECURITY;
ALTER TABLE item_wardrobes ENABLE ROW LEVEL SECURITY;
ALTER TABLE item_pairs ENABLE ROW LEVEL SECURITY;
ALTER TABLE outfit_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE outfit_tags ENABLE ROW LEVEL SECURITY;
ALTER TABLE event_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE event_outfits ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;

-- ============================================
-- ITEMS TABLE POLICIES
-- ============================================

-- Users can select their own items
-- Handle both TEXT and UUID types for user_id
DROP POLICY IF EXISTS "Users can select own items" ON items;
CREATE POLICY "Users can select own items"
ON items FOR SELECT
USING (user_id::text = auth.uid()::text);

-- Users can insert their own items
DROP POLICY IF EXISTS "Users can insert own items" ON items;
CREATE POLICY "Users can insert own items"
ON items FOR INSERT
WITH CHECK (user_id::text = auth.uid()::text);

-- Users can update their own items
DROP POLICY IF EXISTS "Users can update own items" ON items;
CREATE POLICY "Users can update own items"
ON items FOR UPDATE
USING (user_id::text = auth.uid()::text)
WITH CHECK (user_id::text = auth.uid()::text);

-- Users can delete their own items
DROP POLICY IF EXISTS "Users can delete own items" ON items;
CREATE POLICY "Users can delete own items"
ON items FOR DELETE
USING (user_id::text = auth.uid()::text);

-- ============================================
-- REFERENCE TABLES POLICIES (Brands, Categories, etc.)
-- ============================================

-- Brands
DROP POLICY IF EXISTS "Users can manage own brands" ON brands;
CREATE POLICY "Users can manage own brands"
ON brands FOR ALL
USING (user_id::text = auth.uid()::text)
WITH CHECK (user_id::text = auth.uid()::text);

-- Categories
DROP POLICY IF EXISTS "Users can manage own categories" ON categories;
CREATE POLICY "Users can manage own categories"
ON categories FOR ALL
USING (user_id::text = auth.uid()::text)
WITH CHECK (user_id::text = auth.uid()::text);

-- Subcategories
DROP POLICY IF EXISTS "Users can manage own subcategories" ON subcategories;
CREATE POLICY "Users can manage own subcategories"
ON subcategories FOR ALL
USING (user_id::text = auth.uid()::text)
WITH CHECK (user_id::text = auth.uid()::text);

-- Colors
DROP POLICY IF EXISTS "Users can manage own colors" ON colors;
CREATE POLICY "Users can manage own colors"
ON colors FOR ALL
USING (user_id::text = auth.uid()::text)
WITH CHECK (user_id::text = auth.uid()::text);

-- Seasons
DROP POLICY IF EXISTS "Users can manage own seasons" ON seasons;
CREATE POLICY "Users can manage own seasons"
ON seasons FOR ALL
USING (user_id::text = auth.uid()::text)
WITH CHECK (user_id::text = auth.uid()::text);

-- Sizes
DROP POLICY IF EXISTS "Users can manage own sizes" ON sizes;
CREATE POLICY "Users can manage own sizes"
ON sizes FOR ALL
USING (user_id::text = auth.uid()::text)
WITH CHECK (user_id::text = auth.uid()::text);

-- Tags
DROP POLICY IF EXISTS "Users can manage own tags" ON tags;
CREATE POLICY "Users can manage own tags"
ON tags FOR ALL
USING (user_id::text = auth.uid()::text)
WITH CHECK (user_id::text = auth.uid()::text);

-- Locations
DROP POLICY IF EXISTS "Users can manage own locations" ON locations;
CREATE POLICY "Users can manage own locations"
ON locations FOR ALL
USING (user_id::text = auth.uid()::text)
WITH CHECK (user_id::text = auth.uid()::text);

-- Collections
DROP POLICY IF EXISTS "Users can manage own collections" ON collections;
CREATE POLICY "Users can manage own collections"
ON collections FOR ALL
USING (user_id::text = auth.uid()::text)
WITH CHECK (user_id::text = auth.uid()::text);

-- Wardrobes
DROP POLICY IF EXISTS "Users can manage own wardrobes" ON wardrobes;
CREATE POLICY "Users can manage own wardrobes"
ON wardrobes FOR ALL
USING (user_id::text = auth.uid()::text)
WITH CHECK (user_id::text = auth.uid()::text);

-- Outfits
DROP POLICY IF EXISTS "Users can manage own outfits" ON outfits;
CREATE POLICY "Users can manage own outfits"
ON outfits FOR ALL
USING (user_id::text = auth.uid()::text)
WITH CHECK (user_id::text = auth.uid()::text);

-- Events
DROP POLICY IF EXISTS "Users can manage own events" ON events;
CREATE POLICY "Users can manage own events"
ON events FOR ALL
USING (user_id::text = auth.uid()::text)
WITH CHECK (user_id::text = auth.uid()::text);

-- ============================================
-- CHILD TABLES POLICIES
-- ============================================
-- Note: Child tables reference items via item_id, so we join with items to check user_id

-- Item Photos (join with items table to check user_id)
DROP POLICY IF EXISTS "Users can manage own item photos" ON item_photos;
CREATE POLICY "Users can manage own item photos"
ON item_photos FOR ALL
USING (
    EXISTS (
        SELECT 1 FROM items 
        WHERE items.id = item_photos.item_id 
        AND items.user_id::text = auth.uid()::text
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM items 
        WHERE items.id = item_photos.item_id 
        AND items.user_id::text = auth.uid()::text
    )
);

-- Item Prices (join with items table to check user_id)
DROP POLICY IF EXISTS "Users can manage own item prices" ON item_prices;
CREATE POLICY "Users can manage own item prices"
ON item_prices FOR ALL
USING (
    EXISTS (
        SELECT 1 FROM items 
        WHERE items.id = item_prices.item_id 
        AND items.user_id::text = auth.uid()::text
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM items 
        WHERE items.id = item_prices.item_id 
        AND items.user_id::text = auth.uid()::text
    )
);

-- Item Links (join with items table to check user_id)
DROP POLICY IF EXISTS "Users can manage own item links" ON item_links;
CREATE POLICY "Users can manage own item links"
ON item_links FOR ALL
USING (
    EXISTS (
        SELECT 1 FROM items 
        WHERE items.id = item_links.item_id 
        AND items.user_id::text = auth.uid()::text
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM items 
        WHERE items.id = item_links.item_id 
        AND items.user_id::text = auth.uid()::text
    )
);

-- ============================================
-- JUNCTION TABLES POLICIES
-- ============================================
-- Note: Junction tables may have user_id or may need to join with items table

-- Item Colors (join with items table to check user_id)
DROP POLICY IF EXISTS "Users can manage own item colors" ON item_colors;
CREATE POLICY "Users can manage own item colors"
ON item_colors FOR ALL
USING (
    EXISTS (
        SELECT 1 FROM items 
        WHERE items.id = item_colors.item_id 
        AND items.user_id::text = auth.uid()::text
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM items 
        WHERE items.id = item_colors.item_id 
        AND items.user_id::text = auth.uid()::text
    )
);

-- Item Seasons (join with items table to check user_id)
DROP POLICY IF EXISTS "Users can manage own item seasons" ON item_seasons;
CREATE POLICY "Users can manage own item seasons"
ON item_seasons FOR ALL
USING (
    EXISTS (
        SELECT 1 FROM items 
        WHERE items.id = item_seasons.item_id 
        AND items.user_id::text = auth.uid()::text
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM items 
        WHERE items.id = item_seasons.item_id 
        AND items.user_id::text = auth.uid()::text
    )
);

-- Item Tags (join with items table to check user_id)
DROP POLICY IF EXISTS "Users can manage own item tags" ON item_tags;
CREATE POLICY "Users can manage own item tags"
ON item_tags FOR ALL
USING (
    EXISTS (
        SELECT 1 FROM items 
        WHERE items.id = item_tags.item_id 
        AND items.user_id::text = auth.uid()::text
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM items 
        WHERE items.id = item_tags.item_id 
        AND items.user_id::text = auth.uid()::text
    )
);

-- Item Collections (join with items table to check user_id)
DROP POLICY IF EXISTS "Users can manage own item collections" ON item_collections;
CREATE POLICY "Users can manage own item collections"
ON item_collections FOR ALL
USING (
    EXISTS (
        SELECT 1 FROM items 
        WHERE items.id = item_collections.item_id 
        AND items.user_id::text = auth.uid()::text
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM items 
        WHERE items.id = item_collections.item_id 
        AND items.user_id::text = auth.uid()::text
    )
);

-- Item Pairs (join with items table via item_id to check user_id)
-- Both rows of a bidirectional pair share the same item_id owner, so checking item_id is sufficient.
DROP POLICY IF EXISTS "Users can manage own item pairs" ON item_pairs;
CREATE POLICY "Users can manage own item pairs"
ON item_pairs FOR ALL
USING (
    EXISTS (
        SELECT 1 FROM items
        WHERE items.id = item_pairs.item_id
        AND items.user_id::text = auth.uid()::text
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM items
        WHERE items.id = item_pairs.item_id
        AND items.user_id::text = auth.uid()::text
    )
);

-- Item Wardrobes (join with items table to check user_id)
DROP POLICY IF EXISTS "Users can manage own item wardrobes" ON item_wardrobes;
CREATE POLICY "Users can manage own item wardrobes"
ON item_wardrobes FOR ALL
USING (
    EXISTS (
        SELECT 1 FROM items 
        WHERE items.id = item_wardrobes.item_id 
        AND items.user_id::text = auth.uid()::text
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM items 
        WHERE items.id = item_wardrobes.item_id 
        AND items.user_id::text = auth.uid()::text
    )
);

-- Outfit Items (join with outfits table to check user_id)
DROP POLICY IF EXISTS "Users can manage own outfit items" ON outfit_items;
CREATE POLICY "Users can manage own outfit items"
ON outfit_items FOR ALL
USING (
    EXISTS (
        SELECT 1 FROM outfits 
        WHERE outfits.id = outfit_items.outfit_id 
        AND outfits.user_id::text = auth.uid()::text
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM outfits 
        WHERE outfits.id = outfit_items.outfit_id 
        AND outfits.user_id::text = auth.uid()::text
    )
);

-- Outfit Tags (join with outfits table to check user_id)
DROP POLICY IF EXISTS "Users can manage own outfit tags" ON outfit_tags;
CREATE POLICY "Users can manage own outfit tags"
ON outfit_tags FOR ALL
USING (
    EXISTS (
        SELECT 1 FROM outfits 
        WHERE outfits.id = outfit_tags.outfit_id 
        AND outfits.user_id::text = auth.uid()::text
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM outfits 
        WHERE outfits.id = outfit_tags.outfit_id 
        AND outfits.user_id::text = auth.uid()::text
    )
);

-- Event Items (join with events table to check user_id)
DROP POLICY IF EXISTS "Users can manage own event items" ON event_items;
CREATE POLICY "Users can manage own event items"
ON event_items FOR ALL
USING (
    EXISTS (
        SELECT 1 FROM events 
        WHERE events.id = event_items.event_id 
        AND events.user_id::text = auth.uid()::text
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM events 
        WHERE events.id = event_items.event_id 
        AND events.user_id::text = auth.uid()::text
    )
);

-- Event Outfits (join with events table to check user_id)
DROP POLICY IF EXISTS "Users can manage own event outfits" ON event_outfits;
CREATE POLICY "Users can manage own event outfits"
ON event_outfits FOR ALL
USING (
    EXISTS (
        SELECT 1 FROM events 
        WHERE events.id = event_outfits.event_id 
        AND events.user_id::text = auth.uid()::text
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM events 
        WHERE events.id = event_outfits.event_id 
        AND events.user_id::text = auth.uid()::text
    )
);

-- ============================================
-- USER PROFILES POLICIES
-- ============================================

-- User Profiles (users can only access their own profile)
DROP POLICY IF EXISTS "Users can manage own profile" ON user_profiles;
CREATE POLICY "Users can manage own profile"
ON user_profiles FOR ALL
USING (user_id::text = auth.uid()::text)
WITH CHECK (user_id::text = auth.uid()::text);

-- ============================================
-- PACKING CHECKLIST ITEMS POLICIES
-- ============================================

-- Ensure table exists (see SUPABASE_PACKING_CHECKLIST_ITEMS.sql) before running these statements.

ALTER TABLE IF EXISTS packing_checklist_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users manage own packing_checklist_items" ON packing_checklist_items;
CREATE POLICY "Users manage own packing_checklist_items"
ON packing_checklist_items FOR ALL
USING (user_id::text = auth.uid()::text)
WITH CHECK (user_id::text = auth.uid()::text);

-- ============================================
-- PACKING CHECKLIST SECTIONS POLICIES
-- ============================================

-- Ensure table exists (see SUPABASE_PACKING_CHECKLIST_SECTIONS.sql) before running these statements.

ALTER TABLE IF EXISTS packing_checklist_sections ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users manage own packing_checklist_sections" ON packing_checklist_sections;
CREATE POLICY "Users manage own packing_checklist_sections"
ON packing_checklist_sections FOR ALL
USING (user_id::text = auth.uid()::text)
WITH CHECK (user_id::text = auth.uid()::text);

-- ============================================
-- VERIFICATION
-- ============================================

-- To verify RLS is enabled and policies are created, run:
-- SELECT tablename, policyname, permissive, roles, cmd, qual, with_check
-- FROM pg_policies
-- WHERE schemaname = 'public'
-- ORDER BY tablename, policyname;

-- To check if RLS is enabled on a specific table:
-- SELECT tablename, rowsecurity FROM pg_tables WHERE schemaname = 'public' AND tablename = 'items';

-- To test if policies are working, try:
-- SELECT auth.uid()::text;  -- Should return your user ID
-- SELECT user_id FROM items LIMIT 1;  -- Should only return your own items

