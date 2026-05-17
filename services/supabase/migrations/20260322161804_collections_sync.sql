CREATE TABLE collections (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE collection_scans (
    collection_id UUID NOT NULL REFERENCES collections(id) ON DELETE CASCADE,
    scan_id UUID NOT NULL REFERENCES scans(id) ON DELETE CASCADE,
    PRIMARY KEY (collection_id, scan_id)
);

-- Enable RLS
ALTER TABLE collections ENABLE ROW LEVEL SECURITY;
ALTER TABLE collection_scans ENABLE ROW LEVEL SECURITY;

-- RLS Policies for collections
CREATE POLICY "Users can fully manage their own collections" ON collections
    FOR ALL
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- RLS Policies for collection_scans
CREATE POLICY "Users can fully manage their own collection scans" ON collection_scans
    FOR ALL
    USING (
        auth.uid() IN (
            SELECT user_id FROM collections WHERE id = collection_id
        )
    )
    WITH CHECK (
        auth.uid() IN (
            SELECT user_id FROM collections WHERE id = collection_id
        )
    );
