@@ migrations
-- 1 up
create table aliases (id serial primary key, recipient varchar(255), forward_to text);

-- 1 down
drop table if exists aliases;
