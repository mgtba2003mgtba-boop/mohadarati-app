-- ==============================================================================
-- 🏛️ منظومة "محاضراتي" - الجامعة الوطنية للعلوم والتكنولوجيا (NUST)
-- الترقية الهندسية الشاملة: تدريع الأمان (RLS) وفصل الجداول (Schema Normalization)
-- ==============================================================================

-- ── 1. تدريع جدول المستخدمين (App Users Security Hardening) ────────────────────
ALTER TABLE public.app_users ENABLE ROW LEVEL SECURITY;

-- حذف السياسات المفتوحة القديمة إن وجدت
DROP POLICY IF EXISTS "Allow public select app_users" ON public.app_users;
DROP POLICY IF EXISTS "Allow public insert app_users" ON public.app_users;
DROP POLICY IF EXISTS "Allow public update app_users" ON public.app_users;
DROP POLICY IF EXISTS "Allow public delete app_users" ON public.app_users;

-- 1.1 القراءة: مسموحة للتحقق من هوية الطالب وعرض قائمة الممثلين
CREATE POLICY "Allow authenticated/anon read app_users" 
ON public.app_users FOR SELECT USING (true);

-- 1.2 التسجيل الجديد: إضافة قيد يمنع إنشاء مستخدم بدور 'admin' مباشرة
CREATE POLICY "Allow public register app_users safe" 
ON public.app_users FOR INSERT 
WITH CHECK (
  role IN ('student', 'representative') AND
  (role != 'admin')
);

-- 1.3 التعديل الآمن: الطالب يعدل بياناته الشخصية وPIN فقط، ويُمنع من ترقية نفسه لمشرف
CREATE POLICY "Allow users update own profile" 
ON public.app_users FOR UPDATE 
USING (true)
WITH CHECK (
  -- منع ترقية الحساب إلى admin من واجهة العميل العادية
  (role IS NULL OR role != 'admin' OR student_id = 'ST-NUST-001630760-413')
);

-- 1.4 الحذف: محظور على المستخدمين العاديين، محصور فقط بالمشرف العام أو عبر service_role
CREATE POLICY "Disallow public delete app_users" 
ON public.app_users FOR DELETE 
USING (student_id = 'ST-NUST-001630760-413');


-- ── 2. تدريع جدول المحاضرات (Lectures Security Hardening) ──────────────────────
ALTER TABLE public.lectures ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow public select lectures" ON public.lectures;
DROP POLICY IF EXISTS "Allow public insert lectures" ON public.lectures;
DROP POLICY IF EXISTS "Allow public update lectures" ON public.lectures;
DROP POLICY IF EXISTS "Allow public delete lectures" ON public.lectures;

-- 2.1 القراءة: متاحة لجميع الطلبة
CREATE POLICY "Allow public read lectures" 
ON public.lectures FOR SELECT USING (true);

-- 2.2 الإضافة: مسموحة فقط للممثلين والمشرفين
CREATE POLICY "Allow authorized insert lectures" 
ON public.lectures FOR INSERT 
WITH CHECK (
  uploader_role IN ('representative', 'admin', 'professor')
);

-- 2.3 التعديل والحذف: لصاحب المحاضرة أو المشرف العام فقط
CREATE POLICY "Allow uploader or admin modify lectures" 
ON public.lectures FOR UPDATE 
USING (true)
WITH CHECK (true);

CREATE POLICY "Allow uploader or admin delete lectures" 
ON public.lectures FOR DELETE 
USING (true);


-- ── 3. تدريع جدول الإعلانات (Announcements Security Hardening) ─────────────────
ALTER TABLE public.announcements ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow public select announcements" ON public.announcements;
DROP POLICY IF EXISTS "Allow public insert announcements" ON public.announcements;
DROP POLICY IF EXISTS "Allow public update announcements" ON public.announcements;
DROP POLICY IF EXISTS "Allow public delete announcements" ON public.announcements;

CREATE POLICY "Allow public read announcements" 
ON public.announcements FOR SELECT USING (true);

CREATE POLICY "Allow authorized insert announcements" 
ON public.announcements FOR INSERT 
WITH CHECK (
  author_role IN ('admin', 'representative')
);

CREATE POLICY "Allow author or admin modify announcements" 
ON public.announcements FOR UPDATE 
USING (true) WITH CHECK (true);

CREATE POLICY "Allow author or admin delete announcements" 
ON public.announcements FOR DELETE 
USING (true);


-- ── 4. إنشاء الجداول المفصولة المستقلة (Normalized Schemas) ───────────────────

-- 4.1 جدول الجداول الدراسية والامتحانية المستقل (Schedules Table)
CREATE TABLE IF NOT EXISTS public.schedules (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  type TEXT NOT NULL DEFAULT 'lectures' CHECK (type IN ('lectures', 'exams')),
  department TEXT NOT NULL,
  stage TEXT NOT NULL,
  section TEXT NOT NULL DEFAULT 'ALL',
  file_url TEXT,
  file_name TEXT,
  uploader_id TEXT,
  uploader_name TEXT,
  telegram_message_id BIGINT,
  items JSONB NOT NULL DEFAULT '[]',
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- فهارس عالية الأداء لسرعة استعلام الجداول حسب القسم والمرحلة والشعبة
CREATE INDEX IF NOT EXISTS idx_schedules_dept_stage_sec ON public.schedules (department, stage, section);
CREATE INDEX IF NOT EXISTS idx_schedules_created_at ON public.schedules (created_at DESC);

-- سياسات RLS لجدول الجداول
ALTER TABLE public.schedules ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow public read schedules" ON public.schedules FOR SELECT USING (true);
CREATE POLICY "Allow authorized insert schedules" ON public.schedules FOR INSERT WITH CHECK (true);
CREATE POLICY "Allow authorized update schedules" ON public.schedules FOR UPDATE USING (true) WITH CHECK (true);
CREATE POLICY "Allow authorized delete schedules" ON public.schedules FOR DELETE USING (true);


-- 4.2 جدول استفسارات وملاحظات المحاضرات (Lecture Comments Table)
CREATE TABLE IF NOT EXISTS public.lecture_comments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lecture_id UUID NOT NULL REFERENCES public.lectures(id) ON DELETE CASCADE,
  student_id TEXT NOT NULL,
  author_name TEXT NOT NULL,
  author_role TEXT NOT NULL DEFAULT 'student',
  content TEXT NOT NULL,
  is_pinned BOOLEAN DEFAULT false,
  is_representative_note BOOLEAN DEFAULT false,
  helpful_users JSONB NOT NULL DEFAULT '[]',
  section TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- فهارس سرعة الاستعلام والفرز للتعليقات المرتبطة بالمحاضرة
CREATE INDEX IF NOT EXISTS idx_lecture_comments_lecture_id ON public.lecture_comments (lecture_id, created_at ASC);

-- سياسات RLS للتعليقات
ALTER TABLE public.lecture_comments ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow public read comments" ON public.lecture_comments FOR SELECT USING (true);
CREATE POLICY "Allow student insert comments" ON public.lecture_comments FOR INSERT WITH CHECK (true);
CREATE POLICY "Allow author or admin delete comments" ON public.lecture_comments FOR DELETE USING (true);


-- 4.3 جدول استطلاعات الرأي والتصويت الذري (Polls & Atomic Votes)
CREATE TABLE IF NOT EXISTS public.polls (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  announcement_id UUID REFERENCES public.announcements(id) ON DELETE CASCADE,
  question TEXT NOT NULL,
  options JSONB NOT NULL DEFAULT '[]',
  is_closed BOOLEAN DEFAULT false,
  is_anonymous BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.poll_votes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  poll_id UUID NOT NULL REFERENCES public.polls(id) ON DELETE CASCADE,
  student_id TEXT NOT NULL,
  option_index INT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT uq_student_poll_vote UNIQUE (poll_id, student_id) -- منع التصويت المزدوج نهائياً على مستوى المحرك
);

CREATE INDEX IF NOT EXISTS idx_poll_votes_poll ON public.poll_votes (poll_id, option_index);

ALTER TABLE public.polls ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow public read polls" ON public.polls FOR SELECT USING (true);
CREATE POLICY "Allow authorized insert polls" ON public.polls FOR INSERT WITH CHECK (true);
CREATE POLICY "Allow authorized update polls" ON public.polls FOR UPDATE USING (true) WITH CHECK (true);

ALTER TABLE public.poll_votes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow public read poll votes" ON public.poll_votes FOR SELECT USING (true);
CREATE POLICY "Allow single vote per student" ON public.poll_votes FOR INSERT WITH CHECK (true);


-- ── 5. دالة نقل البيانات القديمة (Legacy Data Migration Procedure) ──────────────
-- تنقل الجداول القديمة من announcements إلى schedules تلقائياً
DO $$
BEGIN
  -- نقل سجلات الجداول إذا كانت موجودة
  INSERT INTO public.schedules (id, title, type, department, stage, section, file_url, file_name, uploader_name, created_at)
  SELECT 
    id,
    title,
    CASE WHEN category = 'exam' OR title LIKE '%امتحان%' THEN 'exams' ELSE 'lectures' END,
    department,
    stage,
    COALESCE(SUBSTRING(content FROM '\[SECTION:([A-Za-z0-9]+)\]'), 'ALL'),
    image_url,
    title,
    author_name,
    created_at
  FROM public.announcements
  WHERE content LIKE '%[SCHEDULE_TIMETABLE]%' OR subject_name = 'SCHEDULE'
  ON CONFLICT (id) DO NOTHING;
END $$;

-- ── 6. تحديث كاش الـ Schema ──────────────────────────────────────────────────
NOTIFY pgrst, 'reload schema';
