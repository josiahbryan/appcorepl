use strict;

package BryanBlogs::Blog;
{
	our $DbPassword = '';
	$DbPassword = AppCore::Common->read_file('mods/ThemeBryanBlogs/pci_db_password.txt') if -f 'mods/ThemeBryanBlogs/pci_db_password.txt';
	{
		$DbPassword =~ s/[\r\n]//g;
	}
	
	our @DbConfig = (
	
		db		=> 'jblog',
		db_host		=> 'database',
		db_user		=> 'root',
		db_pass		=> $BryanBlogs::Blog::DbPassword,
	);
	
	use base 'AppCore::DBI';
	
	sub home_blog
	{
		my $self = shift;
		my $user = shift;
		my $id = $user->data->get('bryanblogs_legacy_userid');
		return $self->by_field( ownerid => $id);
	}
	
	sub latest_post
	{
		my $self = shift;
		my $dbh = $self->db_Main;
		my $sth = $dbh->prepare('select max(postid) as max from posts where blogid=?');
		$sth->execute($self->id);
		return $sth->rows ? BryanBlogs::Post->retrieve($sth->fetchrow) : undef;
	}
	
	__PACKAGE__->meta({
		class_noun	=> 'Blog',
		table		=> 'blogs',
		
		@BryanBlogs::Blog::DbConfig,
		
		schema	=>
		[
			{
				'field'	=> 'blogid',
				'extra'	=> 'auto_increment',
				'type'	=> 'int(11)',
				'key'	=> 'PRI',
				readonly=> 1,
				auto	=> 1,
			},
			
# 			+-----------------+--------------+------+-----+---------+----------------+
# 			| blogid          | int(11)      | NO   | PRI | NULL    | auto_increment |
# 			| ownerid         | int(11)      | NO   |     | 0       |                |
# 			| groupid         | int(11)      | YES  |     | NULL    |                |
# 			| folder_name     | varchar(255) | NO   |     |         |                |
# 			| title           | varchar(255) | YES  |     | NULL    |                |
# 			| tagline         | varchar(255) | YES  |     | NULL    |                |
# 			| description     | text         | YES  |     | NULL    |                |
# 			| lastupdated     | datetime     | YES  |     | NULL    |                |
# 			| num_views       | int(11)      | NO   |     | 0       |                |
# 			| num_reminders   | int(11)      | NO   |     | 0       |                |
# 			| auth_required   | int(11)      | NO   |     | 1       |                |
# 			| lastcomment     | datetime     | YES  |     | NULL    |                |
# 			| enable_autosave | int(1)       | NO   |     | 1       |                |
# 			| enable_editor   | int(1)       | NO   |     | 1       |                |
# 			| phone_pass      | varchar(10)  | YES  |     | NULL    |                |
# 			| email_posts     | int(1)       | NO   |     | 1       |                |
# 			| email_comments  | int(1)       | NO   |     | 1       |                |
# 			| email_likes     | int(1)       | NO   |     | 1       |                |
# 			+-----------------+--------------+------+-----+---------+----------------+

			{	field	=> 'ownerid',		type	=> 'int(11)' },
			{	field	=> 'groupid',		type	=> 'int(11)' },
			{	field	=> 'folder_name',	type	=> 'varchar(255)' },
			{	field	=> 'title',		type	=> 'varchar(255)' },
			{	field	=> 'tagline',		type	=> 'varchar(255)' },
			{	field	=> 'lastupdated',	type	=> 'datetime' },
			{	field	=> 'num_views',		type	=> 'int(11)', default => 0 },
			{	field	=> 'num_reminders',	type	=> 'int(11)', default => 0 },
			{	field	=> 'auth_required',	type	=> 'int(1)',  default => 1 },
			{	field	=> 'lastcomment',	type	=> 'datetime' },
			{	field	=> 'enable_autosave',	type	=> 'int(1)',  default => 1 },
			{	field	=> 'enable_editor',	type	=> 'int(1)',  default => 1 },
			{	field	=> 'phone_pass',	type	=> 'varchar(10)' },
			{	field	=> 'email_posts',	type	=> 'int(1)',  default => 1 },
			{	field	=> 'email_comments',	type	=> 'int(1)',  default => 1 },
			{	field	=> 'email_likes',	type	=> 'int(1)',  default => 1 },
		]	
	
	});
	
	sub apply_mysql_schema
	{
		my $self = shift;
# 		my @db_objects = qw{
# 			BryanBlogs::Blog
# 			BryanBlogs::Blog::Post
# 			BryanBlogs::Blog::Post::Like
# 			BryanBlogs::Blog::Post::Tag
# 			BryanBlogs::Blog::Comment
# 			BryanBlogs::Blog::Comment::Like
# 			BryanBlogs::Blog::ReadFlag
# 			BryanBlogs::Blog::ReadPostFlag
# 			BryanBlogs::Blog::ReadCommentFlag
# 		};
# 		$self->mysql_schema_update($_) foreach @db_objects;
	}
};


package BryanBlogs::Post;
{
	our $MAX_FOLDER_LENGTH = 30;
	
	use AppCore::Web::Common;
	use base 'AppCore::DBI';
	
	__PACKAGE__->meta({
		table		=> 'posts',
		
		@BryanBlogs::Blog::DbConfig,
		
		schema	=>
		[
			{
				'field'	=> 'postid',
				'extra'	=> 'auto_increment',
				'type'	=> 'int(11)',
				'key'	=> 'PRI',
				readonly=> 1,
				auto	=> 1,
			},
			{	field	=> 'blogid',		type	=> 'int(11)',		default => 0,		null => 'NO', linked => 'BryanBlogs::Blog' },
			{	field	=> 'postdate',		type	=> 'datetime' },
			{	field	=> 'title',		type	=> 'varchar(255)' },
			{	field	=> 'content',		type	=> 'longtext' },
			{	field	=> 'num_views',		type	=> 'int(11)',		default => 0,		null => 'NO' },
			{	field	=> 'draft_flag',	type	=> "enum('yes','no')",	default => 'no',	null => 'NO' },
			{	field	=> 'draft_time',	type	=> 'datetime' },
			{	field	=> 'attribute_data',	type	=> 'longtext' },
			{	field	=> 'deleted',		type	=> 'int(1)' },
			{	field	=> 'folder_name',	type	=> 'varchar(255)' },
			{	field	=> 'tags',		type	=> 'text' },
		]
	});
	
	sub first_paragraph
	{
		my $self = shift;
		my $content = $self->content;
		my @paragraphs = split /<\/p>/, $content;
		my $first_p = shift @paragraphs;
		$first_p =~ s/^(\n|.)*<p>//g;
		
		$first_p = AppCore::Web::Common->html2text($first_p);
		
		my $max_len = 255;
		$first_p = substr($first_p, 0,$max_len) . '...' if length($first_p) > $max_len;
		
		return $first_p;
	}
	
	sub simple_image_html
	{
		my $str = shift;
		if(index($str,'|') > -1)
		{
			my ($small,$big) = split /\|/, $str;
			return "<a href='$big'><img src='$small' border='0' class='photo'></a>";
		}
		else
		{
			return "<img src='$str' border='0' class='photo'>";
		}
	}

	sub get_content
	{
		my $self = shift;
		my $content = shift || $self->content;
		
		# Add '#more' marker to end of first paragraph
		$content =~ s/<\/p>/<a name='more'>&nbsp;<\/a><\/p>/;
		
		# Fix plaintext blogs
		if(index($content,'<') < 0)
		{
			$content =~ s/\n/<br>\n/g;
			$content =~ s/_{2,}/<br><br>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;/g;
			$content =~ s/(\s{2,})/'&nbsp;' x length($1)/segi;
			$content =~ s/\[photo:([^\]]+)\]/simple_image_html($1)/segi;
		}

		# Add youtube player
		if($content =~ /youtube.com\/watch/)
		{
			my ($url) = $content =~ /(http:\/\/www.youtube.com\/watch[^\s\<]+)/;
			my ($code) = $url =~ /v=([^\&]+)/;
			$content =~ s/(http:\/\/www.youtube.com\/watch[^\s\<]+)/<iframe title="YouTube video player" width="480" height="390" src="http:\/\/www.youtube.com\/embed\/$code" frameborder="0" allowfullscreen><\/iframe>/i;
		}
		
		return $content;
	}
	
	sub normalize_tags
	{
		my $self = shift;
		my $data = $self->tags;
		return '' if !$data;
		my @tags = split /,/, $data;
		s/(^\s+|\s+$)//g foreach @tags;
		#$_ = "#${_}" foreach @tags;
		return join ',', @tags;
	}
	
	sub index_tags
	{
		my $self = shift;
		my $postid = $self->postid;
		my $tag_list = $self->tags;
		my @tags = split /,/, normalize_tags($tag_list);
		my $dbh = $self->db_main;
		$dbh->do('delete from post_tags where postid=?',undef,$postid);
		my $sth = $dbh->prepare('insert into post_tags (postid,tag) values (?,?)');
		$sth->execute($postid,$_) foreach @tags;
	}

	sub make_folder_name
	{
		my $class = shift;
		my $string = lc shift;
		my $disable_trim = shift || 0;
		my $disable_stops = shift || 0;
		
		if(!$disable_stops)
		{
			AppCore::Web::Common->remove_stopwords(\$string);
		}
		
		$string =~ s/['"\[\]\(\)]//g; #"'
		$string =~ s/[^\w]/_/g;
		$string =~ s/\_{2,}/_/g;
		$string =~ s/(^\_+|\_+$)//g;
		$string = substr($string,0,$MAX_FOLDER_LENGTH) if length($string) > $MAX_FOLDER_LENGTH && !$disable_trim;
		return $string;
	}
	
	sub pick_folder_name
	{
		my $post = shift;
		my $title = shift || $post->title;
		
		my $folder = $post->make_folder_name($title);
		
		$folder = $post->make_folder_name($title,0,1) if !$folder;
		$folder = 'no_title_causes_framitz_reduction' if !$folder;
		
		if($post->by_field(folder_name => $folder))
		{
			$folder .= '_'.$post->id;
		}
		
		#print "\nFolder '$folder' generated from subject '".$post->title."'\n";
		
		$post->folder_name($folder);
		$post->update;
	}
	
	sub fix_null_folders
	{
		my $class = shift;
		my @all = $class->retrieve_from_sql('folder_name is NULL');
		my $counter = 0;
		foreach my $post (@all)
		{
			print STDERR "Working on postid $post, # $counter/$#all ... ";
			 
			$post->pick_folder_name;
			
			$counter ++;
		}
	}
	
};

package BryanBlogs::Post::Like;
{
	use base 'AppCore::DBI';
	
	__PACKAGE__->meta({
		table		=> 'post_likes',
		
		@BryanBlogs::Blog::DbConfig,
		
		schema	=>
		[
			{
				'field'	=> 'lineid',
				'extra'	=> 'auto_increment',
				'type'	=> 'int(11)',
				'key'	=> 'PRI',
				readonly=> 1,
				auto	=> 1,
			},
			{	field	=> 'postid',		type	=> 'int(11)', linked => 'BryanBlogs::Post' },
			{	field	=> 'userid',		type	=> 'int(11)' },
			{	field	=> 'timestamp',		type	=> 'timestamp',	default => 'CURRENT_TIMESTAMP',	null => 'NO' },
		]
	});
};


package BryanBlogs::Post::Tag;
{
	use base 'AppCore::DBI';
	
	__PACKAGE__->meta({
		table		=> 'post_tags',
		
		@BryanBlogs::Blog::DbConfig,
		
		schema	=>
		[
			{
				'field'	=> 'lineid',
				'extra'	=> 'auto_increment',
				'type'	=> 'int(11)',
				'key'	=> 'PRI',
				readonly=> 1,
				auto	=> 1,
			},
			{	field	=> 'postid',		type	=> 'int(11)', linked => 'BryanBlogs::Post' },
			{	field	=> 'tag',		type	=> 'varchar(255)' },
		]
	});
};

package BryanBlogs::Comment;
{
	use base 'AppCore::DBI';
	
	__PACKAGE__->meta({
		table		=> 'comments',
		
		@BryanBlogs::Blog::DbConfig,
		
		schema	=>
		[
			{
				'field'	=> 'commentid',
				'extra'	=> 'auto_increment',
				'type'	=> 'int(11)',
				'key'	=> 'PRI',
				readonly=> 1,
				auto	=> 1,
			},
			{	field	=> 'postid',		type	=> 'int(11)',	default => 0,	null => 'NO', linked => 'BryanBlogs::Post' },
			{	field	=> 'commentor',		type	=> 'varchar(255)',	default => ,	null => 'NO' },
			{	field	=> 'timestamp',		type	=> 'timestamp',	default => 'CURRENT_TIMESTAMP',	null => 'NO' },
			{	field	=> 'parentcomment',	type	=> 'int(11)' },
			{	field	=> 'comment',		type	=> 'text' },
			{	field	=> 'email',		type	=> 'varchar(255)' },
			{	field	=> 'subject',		type	=> 'varchar(255)' },
		]
	});
};

package BryanBlogs::Comment::Like;
{
	use base 'AppCore::DBI';
	
	__PACKAGE__->meta({
		table		=> 'comment_likes',
		
		@BryanBlogs::Blog::DbConfig,
		
		schema	=>
		[
			{
				'field'	=> 'lineid',
				'extra'	=> 'auto_increment',
				'type'	=> 'int(11)',
				'key'	=> 'PRI',
				readonly=> 1,
				auto	=> 1,
			},
			{	field	=> 'commentid',		type	=> 'int(11)', linked => 'BryanBlogs::Comment' },
			{	field	=> 'userid',		type	=> 'int(11)' },
			{	field	=> 'timestamp',		type	=> 'timestamp',	default => 'CURRENT_TIMESTAMP',	null => 'NO' },
		]
	});
};

package BryanBlogs::ReadFlag;
{
	use base 'AppCore::DBI';
	
	__PACKAGE__->meta({
		table		=> 'read_flags',
		
		@BryanBlogs::Blog::DbConfig,
		
		schema	=>
		[
			{
				'field'	=> 'lineid',
				'extra'	=> 'auto_increment',
				'type'	=> 'int(11)',
				'key'	=> 'PRI',
				readonly=> 1,
				auto	=> 1,
			},
			{	field	=> 'blogid',		type	=> 'int(11)' },
			{	field	=> 'type',		type	=> "enum('post','comment')" },
			{	field	=> 'userid',		type	=> 'int(11)' },
		]
	});
	
	sub clear_read_flags
	{
		my $class = shift;
		my $blogid = shift;
		my $type = shift;
		$class->db_Main->do('delete from jblog.read_flags where blogid=? and type=?',undef,$blogid,$type);
	}
	
	sub check_read_flag
	{
		my $class = shift;
		my $blogid = shift;
		my $type = shift;
		my $sth = $class->db_Main->prepare('select count(lineid) as `flag` from jblog.read_flags where blogid=? and type=? and userid=?');
		my $user = AppCore::Common->context->user;
		my $empid = $user ? $user->data->get('bryanblogs_legacy_userid') : undef;
		$sth->execute($blogid,$type,$empid);
		return $sth->rows ? $sth->fetchrow_hashref->{flag} + 0:0;
	}
	
	sub set_read_flag
	{
		my $class = shift;
		my $blogid = shift;
		my $type = shift;
		my $user = AppCore::Common->context->user;
		my $empid = $user ? $user->data->get('bryanblogs_legacy_userid') : undef;
		$class->db_Main->do('insert into jblog.read_flags (blogid,type,userid) values(?,?,?)',undef,$blogid,$type,$empid);
	}
	
	
	my $sth_clear_comment_read_flags = undef;
	sub clear_comment_read_flags
	{
		my $class = shift;
		my $commentid = shift;
		my $sth = $sth_clear_comment_read_flags ||= $class->db_Main->prepare('delete from jblog.read_comment_flags where commentid=?');
		$sth->execute($commentid);
	}
	
	my $sth_check_comment_read_flag = undef;
	sub check_comment_read_flag
	{
		my $class = shift;
		my $commentid = shift;
		my $sth = $sth_check_comment_read_flag ||= $class->db_Main->prepare('select count(lineid) as `flag` from jblog.read_comment_flags where commentid=? and userid=?');
		my $user = AppCore::Common->context->user;
		my $empid = $user ? $user->data->get('bryanblogs_legacy_userid') : undef;
		$sth->execute($commentid,$empid);
		return $sth->rows ? $sth->fetchrow_hashref->{flag} + 0:0;
	}
	
	sub set_comment_read_flag
	{
		my $class = shift;
		my $commentid = shift;
		my $type = shift;
		my $user = AppCore::Common->context->user;
		my $empid = $user ? $user->data->get('bryanblogs_legacy_userid') : undef;
		$class->db_Main->do('insert into jblog.read_comment_flags (commentid,userid) values(?,?)',undef,$commentid,$empid);
	}
	
	## per post read flags
	sub clear_post_read_flags
	{
		my $class = shift;
		my $postid = shift;
		my $type = shift;
		$class->db_Main->do('delete from jblog.read_post_flags where postid=? and type=?',undef,$postid,$type);
	}
	
	sub check_post_read_flag
	{
		my $class = shift;
		my $postid = shift;
		my $type = shift;
		my $sth = $class->db_Main->prepare('select count(lineid) as `flag` from jblog.read_post_flags where postid=? and type=? and userid=?');
		my $user = AppCore::Common->context->user;
		my $empid = $user ? $user->data->get('bryanblogs_legacy_userid') : undef;
		$sth->execute($postid,$type,$empid);
		return $sth->rows ? $sth->fetchrow_hashref->{flag} + 0:0;
	}
	
	sub set_post_read_flag
	{
		my $class = shift;
		my $postid = shift;
		my $type = shift;
		my $user = AppCore::Common->context->user;
		my $empid = $user ? $user->data->get('bryanblogs_legacy_userid') : undef;
		$class->db_Main->do('insert into jblog.read_post_flags (postid,type,userid) values(?,?,?)',undef,$postid,$type,$empid);
	}
	

};

package BryanBlogs::ReadPostFlag;
{
	use base 'AppCore::DBI';
	
	__PACKAGE__->meta({
		table		=> 'read_post_flags',
		
		@BryanBlogs::Blog::DbConfig,
		
		schema	=>
		[
			{
				'field'	=> 'lineid',
				'extra'	=> 'auto_increment',
				'type'	=> 'int(11)',
				'key'	=> 'PRI',
				readonly=> 1,
				auto	=> 1,
			},
			{	field	=> 'postid',		type	=> 'int(11)', linked => 'BryanBlogs::Post' },
			{	field	=> 'type',		type	=> "enum('post','comment')" },
			{	field	=> 'userid',		type	=> 'int(11)' },
		]
	});
};

package BryanBlogs::ReadCommentFlag;
{
	use base 'AppCore::DBI';
	
	__PACKAGE__->meta({
		table		=> 'read_comment_flags',
		
		@BryanBlogs::Blog::DbConfig,
		
		schema	=>
		[
			{
				'field'	=> 'lineid',
				'extra'	=> 'auto_increment',
				'type'	=> 'int(11)',
				'key'	=> 'PRI',
				readonly=> 1,
				auto	=> 1,
			},
			{	field	=> 'commentid',		type	=> 'int(11)', linked => 'BryanBlogs::Comment' },
			{	field	=> 'userid',		type	=> 'int(11)' },
		]
	});
};

1;



