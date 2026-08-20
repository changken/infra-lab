CREATE TABLE todos (
   todo_id varchar(100),
   todo_title varchar(500),
   todo_content text,
   created_at date,
   update_at date,
   completed_at date,
   creator varchar(10),
   editor varchar(10),
constraint pk_todo_id primary key(todo_id)
);

CREATE INDEX idx_completed_at ON todos (completed_at);

insert into todos (todo_id, todo_title, todo_content, created_at, creator)
values('20260626204059123', '你好世界', '我們四', now(), 'ken');