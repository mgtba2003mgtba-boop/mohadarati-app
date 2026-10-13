-- ==============================================================================
-- 🏛️ الجامعة الوطنية للعلوم والتكنولوجيا (NUST) - الكلية التقنية الهندسية
-- نظام تطبيق الطالب والمحاضرات والإعلانات ولوحة التحكم (Flutter App Schema)
-- ==============================================================================

-- 1. جدول حسابات مستخدمي التطبيق (App Users & Roles)
CREATE TABLE IF NOT EXISTS public.app_users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id TEXT UNIQUE REFERENCES public.students(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  department TEXT NOT NULL,
  stage TEXT NOT NULL,
  section TEXT,
  phone TEXT,
  email TEXT,
  pin_code TEXT, -- رمز PIN سريع من 4 أو 6 أرقام لتسهيل تسجيل الدخول المتكرر
  role TEXT NOT NULL DEFAULT 'student' CHECK (role IN ('student', 'representative', 'professor', 'admin')),
  can_publish_lectures BOOLEAN DEFAULT false,
  can_publish_announcements BOOLEAN DEFAULT false,
  is_approved BOOLEAN DEFAULT true,
  photo_url TEXT,
  last_login TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- سياسات RLS لجدول المستخدمين
ALTER TABLE public.app_users ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow public select app_users" ON public.app_users FOR SELECT USING (true);
CREATE POLICY "Allow public insert app_users" ON public.app_users FOR INSERT WITH CHECK (true);
CREATE POLICY "Allow public update app_users" ON public.app_users FOR UPDATE USING (true) WITH CHECK (true);
CREATE POLICY "Allow public delete app_users" ON public.app_users FOR DELETE USING (true);

-- 2. جدول الإعلانات الأكاديمية (Announcements)
CREATE TABLE IF NOT EXISTS public.announcements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  content TEXT NOT NULL,
  author_id TEXT NOT NULL,
  author_name TEXT NOT NULL,
  author_role TEXT NOT NULL DEFAULT 'admin',
  department TEXT NOT NULL DEFAULT 'ALL', -- 'ALL' للكلية بالكامل أو اسم القسم
  stage TEXT NOT NULL DEFAULT 'ALL',       -- 'ALL' أو '1', '2', '3', '4'
  category TEXT NOT NULL DEFAULT 'academic', -- 'academic', 'exam', 'urgent', 'activity'
  is_pinned BOOLEAN DEFAULT false,
  image_url TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- سياسات RLS لجدول الإعلانات
ALTER TABLE public.announcements ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow public select announcements" ON public.announcements FOR SELECT USING (true);
CREATE POLICY "Allow public insert announcements" ON public.announcements FOR INSERT WITH CHECK (true);
CREATE POLICY "Allow public update announcements" ON public.announcements FOR UPDATE USING (true) WITH CHECK (true);
CREATE POLICY "Allow public delete announcements" ON public.announcements FOR DELETE USING (true);

-- 3. جدول المحاضرات والمقررات مع روابط Google Drive (Lectures)
CREATE TABLE IF NOT EXISTS public.lectures (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  subject_name TEXT NOT NULL,
  subject_code TEXT,
  department TEXT NOT NULL,
  stage TEXT NOT NULL,
  semester INT NOT NULL DEFAULT 1 CHECK (semester IN (1, 2)),
  type TEXT NOT NULL DEFAULT 'theory' CHECK (type IN ('theory', 'practical')),
  drive_url TEXT NOT NULL,
  description TEXT,
  professor_name TEXT,
  uploader_id TEXT NOT NULL,
  uploader_name TEXT NOT NULL,
  uploader_role TEXT NOT NULL DEFAULT 'representative',
  download_count INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- سياسات RLS لجدول المحاضرات
ALTER TABLE public.lectures ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow public select lectures" ON public.lectures FOR SELECT USING (true);
CREATE POLICY "Allow public insert lectures" ON public.lectures FOR INSERT WITH CHECK (true);
CREATE POLICY "Allow public update lectures" ON public.lectures FOR UPDATE USING (true) WITH CHECK (true);
CREATE POLICY "Allow public delete lectures" ON public.lectures FOR DELETE USING (true);

-- 4. بيانات أولية تجريبية للإعلانات والمحاضرات (Seed Data)
INSERT INTO public.announcements (title, content, author_id, author_name, author_role, department, stage, category, is_pinned)
VALUES 
(
  'مرحباً بكم في تطبيق الكلية الرسمي',
  'نرحب بطلبتنا الأعزاء في المنظومة الطلابية الموحدة لمتابعة الحضور والغياب والمحاضرات وجداول الدوام أولاً بأول.',
  'ADMIN_NUST',
  'عمادة الكلية التقنية الهندسية',
  'admin',
  'ALL',
  'ALL',
  'academic',
  true
),
(
  'تعليمات تسجيل الحضور بالقاعات الذكية',
  'يرجى التأكد من توثيق بصمة الوجه وربط المعرف الجامعي مع بوت التيليجرام لاستلام إشعارات الحضور اللحظية.',
  'ADMIN_NUST',
  'وحدة التسجيل والأنظمة الذكية',
  'admin',
  'ALL',
  'ALL',
  'urgent',
  false
)
ON CONFLICT DO NOTHING;

-- 5. تحديث كاش الـ Schema
NOTIFY pgrst, 'reload schema';
