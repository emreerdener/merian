export interface SyncCollectionPayload {
  id: string;
  name: string;
  created_at: string;
  scan_ids: string[];
  is_deleted?: boolean;
  isDeleted?: boolean;
}

export interface MembershipRow {
  collection_id: string;
  scan_id: string;
}
