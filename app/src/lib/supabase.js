import { createClient } from '@supabase/supabase-js'

// anon key 是公开设计,数据安全由 RLS(仅登录用户)保障
const SUPABASE_URL = 'https://oznaumvwecurqmfjqwne.supabase.co'
const SUPABASE_ANON_KEY = 'sb_publishable_uYTTI6bScMaSHIbgbIkWlQ_cEogOK7F'

export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY)
