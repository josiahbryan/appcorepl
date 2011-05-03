use appcore;
alter table board_posts change attribute_data extra_data longtext;
alter table board_posts change fake_folder_name folder_name varchar(255);

