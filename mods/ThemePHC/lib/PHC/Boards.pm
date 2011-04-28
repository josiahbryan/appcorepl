use strict;

package PHC::Boards;
{
	use AppCore::Common;
	use AppCore::Web::Common;
	
	use base 'AppCore::Web::Module';
	
	use Data::Dumper;
	use HTML::Entities;
	
	#our $ADMIN_ACL = ['Admin-WebBoards','Pastor'];
	
	our $MAX_FOLDER_LENGTH = 225;
	
	our $SUBJECT_LENGTH = 30;

	our $SPAM_OVERRIDE = 0;
	
	# We wouldn't have to do this if we are using blessed objects to call the methods, but since the page handler
	# calls the methods as package methods, we store config options in a package-global bash.
	my $CONFIG_OPTIONS = {};
	sub config
	{
		my $self = shift;
		return $CONFIG_OPTIONS;
	}
	
	#die "z";
	sub init_config
	{
		my $class = shift;
		my %config = (
			short_noun	=> 'Boards',
			long_noun	=> 'Bulletin Boards',
			
			post_reply_tmpl	=> 'pages/boards/post_reply.tmpl',
			new_post_tmpl	=> 'pages/boards/new_post.tmpl',
			post_tmpl	=> 'pages/boards/post.tmpl',
			new_post_tmpl	=> 'pages/boards/new_post.tmpl',
			list_tmpl	=> 'pages/boards/list.tmpl',
			edit_forum_tmpl	=> 'pages/boards/edit_forum.tmpl',
			main_tmpl	=> 'pages/boards/main.tmpl',
			
			admin_acl	=> ['Admin-WebBoards','Pastor'],
		);
		
		$class->apply_config(\%config);
	}
	
	
	sub apply_config
	{
		my $class = shift;
		my $config = shift;
		my $config_ref = $class->config;
		$config_ref->{$_} = $config->{$_} foreach keys %$config;
		
		#print STDERR Dumper $class->config;
	}
	
	sub macro_board_nav
	{
		my $class = shift;
		#print STDERR "path_info: $ENV{PATH_INFO}\n";
		my @path = split/\//, $ENV{PATH_INFO};
		
		shift @path if !$path[0];
		my $first 	= shift @path;
		my $forum 	= shift @path;
		my $post 	= shift @path;
		my $action 	= shift @path;
		#print STDERR "forum=$forum, post=$post, action=$action\n";
		
		
		my $noun = $class->config->{short_noun} || 'Boards';
		
		if($forum)
		{
			my @list;
			my $bin = AppCore::Common->context->http_bin;
			
			my $board = PHC::WebBoard->by_field(folder_name => $forum);
			push @list, "<a href='$bin/$first' class='first'>$noun</a> &raquo; ";
			if($forum ne 'edit' && $forum ne 'new')
			{
				push @list, "<a href='$bin/$first/$forum' class='first ".(!$post || $post eq 'new' ? 'current' : '')."'>".$board->title."</a>" if $board;
				
				if($post && $post ne 'new')
				{
					my $post_ref = PHC::WebBoard::Post->by_field(fake_folder_name => $post);
					if($post_ref)
					{
						$list[$#list].=' &raquo; ';
						push @list, "<a href='$bin/$first/$forum/$post' class='first current'>".$post_ref->subject."</a>";
					}
				}
			}
			
			
			#print STDERR Dumper \@list;
			return '<div class="sub_nav board_nav">You are here: ' . join('',@list) . '</div>';
		}
		else
		{
			#print STDERR "no g children\n";
			return '';
		}
			
	}
	
	sub email_new_post_comments
	{
		my $class = shift;
		my $comment = shift;
		my $comment_url = shift;
		my $email_body = qq{A comment was added by }.$comment->poster_name." to '".$comment->top_commentid->subject.qq{':

    }.AppCore::Web::Common->html2text($comment->text).qq{

Here's a link to that page: 
    http://mypleasanthillchurch.org$comment_url
    
Cheers!};
		#
		AppCore::Web::Common->reset_was_emailed;
		
		my $noun = $class->config->{long_noun} || 'Bulletin Boards';
		
		AppCore::Web::Common->send_email(['jbryan@productiveconcepts.com','pastor@mypleasanthillchurch.org'],"[PHC FORUMS] New Comment Added to Thread '".$comment->top_commentid->subject."'",$email_body);
		AppCore::Web::Common->send_email([$comment->parent_commentid->poster_email],
			"[PHC $noun] New Comment Added to Thread '".$comment->top_commentid->subject."'",$email_body)
				if $comment->parent_commentid && $comment->parent_commentid->id && $comment->parent_commentid->poster_email
				&& !AppCore::Web::Common->was_emailed($comment->top_commentid->poster_email);
		AppCore::Web::Common->send_email([$comment->top_commentid->poster_email],
			"[PHC $noun] New Comment Added to Thread '".$comment->top_commentid->subject."'",$email_body)
				if $comment->top_commentid && $comment->top_commentid->id && $comment->top_commentid->poster_email
				&& !AppCore::Web::Common->was_emailed($comment->top_commentid->poster_email);
		
		
		my $board = $comment->boardid;
		
		AppCore::Web::Common->send_email([$board->managerid->email],
				"[PHC Bulletin Boards] New Comment Added to Thread '".$comment->top_commentid->subject."'",$email_body)
					if $board && $board->id && $board->managerid && $board->managerid->id && $board->managerid->email 
					&& !AppCore::Web::Common->was_emailed($board->managerid->email);
					
		AppCore::Web::Common->reset_was_emailed;
	}
	
	sub create_new_comment
	{
		my $class = shift;
		my $board = shift;
		my $post  = shift;
		my $args  = shift;
		
		# Comment is now hidden, 20090716 JB
		# If it has data, then its probably spam. The visible comment field is named "age"
		if($args->{comment} && !$args->{_internal_} && !$SPAM_OVERRIDE)
		{
			print STDERR "Debug: Ignoring apparent spammer, tried to set comment to '$args->{comment}' [$args->{age}], sending to Wikipedia/Spam_(electronic)\n";
			PHC::Web::Skin->instance->redirect('http://en.wikipedia.org/wiki/Spam_%28electronic%29');
		}
		
		# Now copy the data over to the proper field so I dont have to patch all the code below
		$args->{comment} = $args->{age} if !$args->{_internal_};

		if(!$args->{comment} || length($args->{comment}) < 5)
		{
			return PHC::Web::Skin->instance->error("Empty Comment!","You must enter *something* to comment! [1]");
		}

		
		my $fake_it = $class->to_fake_folder_name($args->{subject});

		# Banned Words Filtering, Added 20090103 by JB
                {
                        require 'ban_words_lib.pl';
                        # Add a space at the end to catch words at the end of the message. Replace all non-letter characters with a space
                        my $clean = $args->{comment};
			$clean =~ s/<[^\>]*>//g; $clean = AppCore::Web::Common->html2text($clean);
                        $clean =~ s/[^\w]/ /g;
                        $clean .= ' ';
                        my ($weight,$matched) = PHC::BanWords::get_phrase_weight($clean);

                        my $user = AppCore::Common->context->user;


                        if($weight >= 5)
                        {
                                PHC::Chat->db_Main->do('insert into chat_rejected (posted_by,poster_name,message,value,list) values (?,?,?,?,?)',undef,
                                        $user,
                                        $user && $user->id ? $user->display : $args->{poster_name},
                                        $args->{comment},
                                        $weight,
                                        join("\n ",@$matched)
                                );

                                print STDERR "===== BANNED ====\nPhrase: '$args->{comment}'\nWeight: $weight\nMatch: \n  ".join("\n  ",@$matched)."\n======
==========\n";
                                die "Sorry, the following word or words are not allowed: \n".join("\n    ",@$matched)."\n Please check your message and try
 again.\nYour original comment:\n$args->{comment}";
                        }
			
			#die "CLEAN:".Dumper ($args,$weight,$matched,$clean);
                }
		
		
		my @tag = $args->{comment} =~ /(<a)/ig;
			
			
		if(
			$args->{poster_name} =~ /\d{2,}/ ||
			$args->{comment} =~ /url=/ ||
			$args->{comment} =~ /link=/ ||
			@tag >= 1)
		{
			#print STDERR "Debug Rejection: comment='$comment', commentor='$commentor'\n";
			die "Sorry, you sound like a spam bot - go away. ($args->{comment})" if !$SPAM_OVERRIDE;
		}
		
		
		#die "x";
		
		
		
		my $append_flag = 0;
		if(my $other = PHC::WebBoard::Post->by_field(fake_folder_name => $fake_it))
		{
			$append_flag = 1;
		}
		
		#die Dumper($fake_it,$append_flag,$args);
		
		$args->{poster_name}  = 'Anonymous' if !$args->{poster_name};
		$args->{poster_email} = 'nobody@example.com' if !$args->{poster_email};
		
		my $comment = PHC::WebBoard::Post->create({
			boardid			=> $board,
			top_commentid		=> $post,
			parent_commentid	=> $args->{parent_commentid},
			poster_name		=> $args->{poster_name},
			poster_email		=> $args->{poster_email},
			posted_by		=> AppCore::Common->context->user,
			timestamp		=> date(),
			subject			=> $args->{subject},
			text			=> $args->{comment},
			fake_folder_name	=> $fake_it,
		});
		
		if($append_flag)
		{
			$comment->fake_folder_name($fake_it.'_'.$comment->id);
			$comment->update;
		}
		
		return $comment;
	}
	
	sub load_post_reply_form
	{
		my $class = shift;
		my $post = shift;
		my $reply_to = shift;
		my $rs = {};
		$rs->{'post_'.$_} = $post->get($_) foreach $post->columns;
		
		if($reply_to)
		{
			my $parent = PHC::WebBoard::Post->by_field(fake_folder_name=>$reply_to);
			$parent = PHC::WebBoard::Post->retrieve($reply_to) if !$parent;
			
			# more fun with spam
			if(!$parent)
			{
				if($reply_to eq 'phc' && !$SPAM_OVERRIDE)
				{
					print STDERR "Debug: Ignoring apparent spammer, tried to load invalid URL, sending to Wikipedia/Spam_(electronic)\n";
					PHC::Web::Skin->instance->redirect('http://en.wikipedia.org/wiki/Spam_%28electronic%29');
				}
				else
				{
					die "Invalid parent $reply_to" if !$parent;
				}
			}
			
			
			$rs->{'reply_'.$_} = $parent->get($_) foreach $parent->columns;
			
			$rs->{subject} = 'Re: '.$parent->subject;
		}
		else
		{
			$rs->{subject} = 'Re: '.$post->subject;
		}
		
		return $rs;
	}
	
	sub post_delete
	{
		my $class = shift;
		my $post = shift;
		my $args = shift;
		
		if($args->{postid})
		{
			my $post = PHC::WebBoard::Post->retrieve($args->{postid});
			$post->deleted(1);
			$post->update;
			
			$post->top_commentid->num_replies($post->top_commentid->num_replies - 1);
			$post->top_commentid->update;
			
			return 'comment';
		}
		else
		{
			$post->top_commentid->num_replies($post->top_commentid->num_replies - 1);
			$post->top_commentid->update;
			
			$post->deleted(1);
			$post->update;
			return 'post';
		}
		
	}
	
	sub can_user_edit
	{
		my $class = shift;
		my $post = shift;
		local $_;
		
		my $can_admin = 1 if ($_ = AppCore::Common->context->user) && $_->check_acl($class->config->{admin_acl});
		
		return $can_admin || (($_ = AppCore::Common->context->user) && $post->posted_by && $_->userid == $post->posted_by->id);
			
	}
	
	sub load_post_edit_form
	{
		my $class = shift;
		my $post = shift;
		my $board = $post->boardid;
		
		my $rs = {};
		$rs->{'post_'.$_} = $post->get($_)   foreach $post->columns;
		$rs->{'board_'.$_} = $board->get($_) foreach $board->columns;
		
		$rs->{post_text} = AppCore::Web::Common->clean_html($rs->{post_text});
		
		return $rs;
	}
			
	sub post_page
	{
		my $class = shift;
		
		my ($section_name,$folder_name,$board_folder_name,$skin,$r,$page,$args,$path) = @_;
		
		#print STDERR "\$section_name=$section_name,\$folder_name=$folder_name,\$board_folder_name=$board_folder_name\n";
		
		my $board = PHC::WebBoard->by_field(folder_name => $board_folder_name);
		
		my $post = PHC::WebBoard::Post->by_field(fake_folder_name => $folder_name);
		if(!$post || $post->deleted)
		{
			return $skin->error("No Such Bulletin Board","Sorry, the folder or action name you gave did not match any existing Bulletin Board folders. Please check your URL or the link on the page that you clicked and try again.");
		}
		
		
		my $sub_page = shift @$path;
		
		#$tmpl->param(can_upload=>1) if ($_ = AppCore::Common->context->user) && $_->check_acl($UPLOAD_ACL);
		
		my $bin = AppCore::Common->context->http_bin;
		
			
		if($sub_page eq 'post')
		{
		
			my $comment = $class->create_new_comment($board,$post,$args);
			
			my $comment_url = "$bin/$section_name/$board_folder_name/$folder_name#c$comment";
			$class->email_new_post_comments($comment,$comment_url);
					
			$r->redirect(AppCore::Common->context->http_bin."/$section_name/$board_folder_name/$folder_name#c$comment");
		}
		elsif($sub_page eq 'reply' || $sub_page eq 'reply_to')
		{
			my $tmpl = $skin->load_template($class->config->{post_reply_tmpl} || 'pages/boards/post_reply.tmpl');
			$tmpl->param(board_nav => $class->macro_board_nav());
			$tmpl->param(pageid => $section_name);
			
			eval
			{
				my $reply_form_resultset = $class->load_post_reply_form($post,shift @$path);
				$tmpl->param($_ => $reply_form_resultset->{$_}) foreach keys %$reply_form_resultset;
			};
			$skin->error("Error Loading Form",$@) if $@;
			#$skin->error("No Such Post","Sorry, the parent comment you gave appears to be invalid.");
			
			$tmpl->param(post_url => "$bin/$section_name/$board_folder_name/$folder_name/post");
			
			return $r->output($tmpl);
				
		}
		elsif($sub_page eq 'delete')
		{
			if(!$class->can_user_edit($post))
			{
				PHC::User::Auth->require_authentication($class->config->{admin_acl});
			}
			
			my $type = $class->post_delete($post,$args);
			
			if($type eq 'comment')
			{
				return $r->redirect("$bin/$section_name/$board_folder_name/$folder_name");
			}
			else
			{
				return $r->redirect("$bin/$section_name/$board_folder_name");
			}
		}
		elsif($sub_page eq 'edit')
		{
			if(!$class->can_user_edit($post))
			{
				$skin->error("Not Allowed","Sorry, you're not allowed to edit this post.");
			}
			
			my $tmpl = $skin->load_template($class->config->{new_post_tmpl} || 'pages/boards/new_post.tmpl');
			$tmpl->param(pageid => $section_name);
			my $board = $post->boardid;
			$tmpl->param(board_nav => $class->macro_board_nav());
			$tmpl->param('folder_'.$board->folder_name => 1);
			
			my $edit_resultset = $class->load_post_edit_form($post);
			$tmpl->param($_ => $edit_resultset->{$_}) foreach keys %$edit_resultset;
			
			$tmpl->param(post_url => "$bin/$section_name/$board_folder_name/$folder_name/save");
			
			return $r->output($tmpl);
		}
		elsif($sub_page eq 'save')
		{
			if(!$class->can_user_edit($post))
			{
				$skin->error("Not Allowed","Sorry, you're not allowed to edit this post.");
			}
			
			$class->post_edit_save($post,$args);
			
			my $folder = $post->fake_folder_name;
			
			my $email_body = $post->poster_name." edited his post '".$post->subject."' in forum '".$board->title.qq{':

    }.AppCore::Web::Common->html2text($args->{comment}).qq{

Here's a link to that page: 
    http://mypleasanthillchurch.org$ENV{SCRIPT_NAME}/$section_name/$board_folder_name/$folder
    
Cheers!};
			
			AppCore::Web::Common->send_email(['jbryan@productiveconcepts.com'],"[PHC FORUMS] Post Edited: '".$post->subject."' in forum '".$board->title."'",$email_body);
		
		
			$r->redirect("$bin/$section_name/$board_folder_name/".$post->fake_folder_name);
				
		}
		else
		{
			my $tmpl = $skin->load_template($class->config->{post_tmpl} || 'pages/boards/post.tmpl');
			$tmpl->param(pageid => $section_name);
			$tmpl->param(board_nav => $class->macro_board_nav());
			
			if($board_folder_name eq 'ask_pastor') #|| $board_folder_name eq 'pastors_blog')
			{
				my $prefix = $post->top_commentid && $post->top_commentid->id ? "c" : "p";
				$r->redirect("$bin/$section_name/$board_folder_name#$prefix".$post->id);
			}

			if($post->top_commentid && $post->top_commentid->id)
			{
				$r->redirect("$bin/$section_name/$board_folder_name/".$post->top_commentid->fake_folder_name."#c".$post->id);
			}
			
			my $post_resultset = $class->load_post($post,$section_name,$board_folder_name);
			$tmpl->param( $_ => $post_resultset->{$_}) foreach keys %$post_resultset;
			
			return $r->output($tmpl);
		}
	}
	
	sub to_fake_folder_name
	{
		my $class = shift;
		my $fake_it = lc shift;
		my $disable_trim = shift || 0;
		$fake_it =~ s/['"\[\]\(\)]//g; #"'
		$fake_it =~ s/[^\w]/_/g;
		$fake_it =~ s/\_{2,}/_/g;
		$fake_it =~ s/(^\_+|\_+$)//g;
		$fake_it = substr($fake_it,0,$MAX_FOLDER_LENGTH) if length($fake_it) > $MAX_FOLDER_LENGTH && !$disable_trim;
		return $fake_it;
		
	}
	
	sub post_edit_save
	{
		my $class = shift;
		my $post = shift;
		my $args = shift;
		
		# The new_post tmpl names the visible comment field 'age' inorder to confuse spammers. The field named 'comment' is hidden,
		# the logic being that if something *is* in the comment field, then its spam. 
		
		# Comment is now hidden, 20090716 JB
		# If it has data, then its probably spam. The visible comment field is named "age"
		if($args->{comment} && !$SPAM_OVERRIDE)
		{
			print STDERR "Debug: Ignoring apparent spammer, tried to set comment to '$args->{comment}', sending to Wikipedia/Spam_(electronic)\n";
			PHC::Web::Skin->instance->redirect('http://en.wikipedia.org/wiki/Spam_%28electronic%29');
		}
		
		# Now copy the data over to the proper field so I dont have to patch all the code below
		$args->{comment} = $args->{age};

		if(!$args->{comment} || length($args->{comment}) < 5)
		{
			return PHC::Web::Skin->instance->error("Empty Comment!","You must enter *something* to comment! [2]");
                }
		
		my $fake_it = $class->to_fake_folder_name($args->{subject});
		if($fake_it ne $post->fake_folder_name && PHC::WebBoard::Post->by_field(fake_folder_name => $fake_it))
		{
			$fake_it .= '_'.$post->id;
		}
		
		#die Dumper $fake_it, $args;
		
		$post->subject($args->{subject});
		$post->text(AppCore::Web::Common->clean_html($args->{comment}));
		$post->fake_folder_name($fake_it);
		$post->update;
		
		return $post;
		
		
	}

	
	
	sub _post_prep_ref
	{
		my $local_ctx = shift;
		my $list = shift;
		my $b = shift;
		$b->{$_} = $b->get($_) foreach $b->columns;
		$b->{bin} 		= $local_ctx->{bin};
		$b->{pageid} 		= $local_ctx->{section_name};
		$b->{folder_name} 	= $local_ctx->{folder_name};
		$b->{indent}		= $local_ctx->{indent}->{$b->parent_commentid};
		$b->{indent_css} 	= $b->{indent} * 2;
		$b->{reply_to_url} 	= $local_ctx->{reply_to_url};
		$b->{can_admin} 	= $local_ctx->{can_admin};
		$b->{delete_url} 	= $local_ctx->{delete_base};
		$b->{can_reply}		= defined $local_ctx->{can_reply} ? $local_ctx->{can_reply} : 1,
		$b->{text} 		=~ s/(^\s+|\s+$)//g;
		$b->{text} 		=~ s/(^<p>|<\/p>$)//g ; #unless index(lc $b->{text},'<p>') > 0;
		$b->{text}		=~ s/((?:http:\/\/www\.|www\.|http:\/\/)[^\s]+)/<a href="$1">$1<\/a>/g;
		$b->{text}		= PHC::VerseLookup->tag_verses($b->{text});
		$local_ctx->{indent}->{$b->id} = $b->{indent} + 1;
		push @$list, $b;
	}
	
	sub _post_add_kids
	{
		my $local_ctx = shift;
		my $list = shift;
		my $b = shift;
		my @kids = PHC::WebBoard::Post->search(deleted=>0,top_commentid=>$local_ctx->{post},parent_commentid=>$b);
		foreach my $kid (@kids)
		{
			_post_prep_ref($local_ctx,$list,$kid);
			_post_add_kids($local_ctx,$list,$kid);
		}
	}
	
	sub load_post
	{
		my $class = shift;
		
		my $post = shift;
		my $section_name = shift;
		my $board_folder_name = shift;
		
		my $dont_count_view = shift || 0;
		
		my $more_local_ctx = shift;
		
		
		my $folder_name = $post->fake_folder_name;
	
		my $bin = AppCore::Common->context->http_bin;
		
		unless($dont_count_view)
		{
			$post->num_views($post->num_views+1);
			$post->update;
		}
		
		my $rs;
		
		my $board = $post->boardid;
		$rs->{'post_'.$_}  = $post->get($_)  foreach $post->columns;
		$rs->{'board_'.$_} = $board->get($_) foreach $board->columns;
		
		$rs->{post_text} = AppCore::Web::Common->clean_html($rs->{post_text});
		
		$rs->{post_text} = PHC::VerseLookup->tag_verses($rs->{post_text});
		
		my $reply_to_url = $bin."/$section_name/$board_folder_name/$folder_name/reply_to";
		my $delete_base = $bin."/$section_name/$board_folder_name/$folder_name/delete";
		
		my $can_admin = 1 if ($_ = AppCore::Common->context->user) && $_->check_acl($class->config->{admin_acl});
		$rs->{can_admin} = $can_admin;
		
		$rs->{can_edit} = $class->can_user_edit($post);
		
		my $list = [];
		
		
		my $local_ctx = 
		{
			post		=> $post,
			bin 		=> $bin,
			section_name	=> $section_name,
			folder_name	=> $folder_name,
			reply_to_url	=> $reply_to_url,
			can_admin	=> $can_admin,
			delete_base	=> $delete_base,
		};
		
		if($more_local_ctx && ref($more_local_ctx) eq 'HASH')
		{
			$local_ctx->{$_} = $more_local_ctx->{$_} foreach keys %$more_local_ctx;
		}
		
		my @replies = PHC::WebBoard::Post->search(deleted=>0,top_commentid=>$post,parent_commentid=>0);
		foreach my $b (@replies)
		{
			_post_prep_ref($local_ctx,$list,$b);
			_post_add_kids($local_ctx,$list,$b);
		}
		
		
		$rs->{replies} = $list;
		
		return $rs;
	}
	
	sub create_new_thread
	{
		my $class = shift;
		my $board = shift;
		my $args = shift;

		print STDERR "create_new_thread: \$SPAM_OVERRIDE=$SPAM_OVERRIDE, args:".Dumper($args);
		
		# Comment is now hidden, 20090716 JB
		# If it has data, then its probably spam. The visible comment field is named "age"
		if($args->{comment} && !$args->{_internal_} && !$SPAM_OVERRIDE)
		{
			print STDERR "Debug: Ignoring apparent spammer, tried to set comment to '$args->{comment}' [$args->{age}], sending to Wikipedia/Spam_(electronic)\n";
			PHC::Web::Skin->instance->redirect('http://en.wikipedia.org/wiki/Spam_%28electronic%29');
		}
		
		#die Dumper $args;
		# Now copy the data over to the proper field so I dont have to patch all the code below
		$args->{comment} = $args->{age};# if !$args->{_internal_};

		if(!$args->{comment} || length($args->{comment}) < 5)
		{
			return PHC::Web::Skin->instance->error("No Text Given!","You must enter *something* in the text box! [3]");
           	}

		# Banned Words Filtering, Added 20090103 by JB
		{
			require 'ban_words_lib.pl';
                        # Add a space at the end to catch words at the end of the message. Replace all non-letter characters with a space
                        my $clean = $args->{comment};
			$clean =~ s/<[^\>]*>//g; 
			$clean = AppCore::Web::Common->html2text($clean);
                        $clean =~ s/[^\w]/ /g;
                        $clean .= ' ';
                        my ($weight,$matched) = PHC::BanWords::get_phrase_weight($clean);

                        my $user = AppCore::Common->context->user;


                        if($weight >= 5)
                        {
                                PHC::Chat->db_Main->do('insert into chat_rejected (posted_by,poster_name,message,value,list) values (?,?,?,?,?)',undef,
                                        $user,
                                        $user && $user->id ? $user->display : $args->{poster_name},
                                        $args->{comment},
                                        $weight,
                                        join("\n ",@$matched)
                                );

                                print STDERR "===== BANNED ====\nPhrase: '$args->{comment}'\nWeight: $weight\nMatch: \n  ".join("\n  ",@$matched)."\n================\n";
				die "Sorry, the following word or words are not allowed: \n".join("\n    ",@$matched)."\n Please check your message and try again.\nYour original comment:\n$args->{comment}";		
			}
		}

		
		if(!$args->{subject})
		{
			my $text = AppCore::Web::Common->html2text($args->{comment});
			$args->{subject} = substr($text,0,$SUBJECT_LENGTH). (length($text) > $SUBJECT_LENGTH ? '...' : '');
		}
		
		
		my $fake_it = $class->to_fake_folder_name($args->{subject});
		
		
		my $append_flag = 0;
		if(my $other = PHC::WebBoard::Post->by_field(fake_folder_name => $fake_it))
		{
			$append_flag = 1;
		}
		
		$args->{poster_name}  = 'Anonymous'          if !$args->{poster_name};
		$args->{poster_email} = 'nobody@example.com' if !$args->{poster_email};
		
		my $post = PHC::WebBoard::Post->create({
			boardid			=> $board->id,
			poster_name		=> $args->{poster_name},
			poster_email		=> $args->{poster_email},
			posted_by		=> AppCore::Common->context->user,
			timestamp		=> date(),
			subject			=> $args->{subject},
			text			=> $args->{comment},
			fake_folder_name	=> $fake_it,
		});
		
		if($append_flag)
		{
			$fake_it = $fake_it.'_'.$post->id;
			$post->fake_folder_name($fake_it);
			$post->update;
		}
		
		return $post;
			
	}
	
	sub email_new_post
	{
	
		my $class = shift;
		my $post = shift;
		my $section_name = shift;
		my $folder_name = shift;
		
		my $fake_it = $post->fake_folder_name;
		my $board = $post->boardid;
		
		my $email_body = qq{A new post was added by }.$post->poster_name." in forum '".$board->title.qq{':

    }.AppCore::Web::Common->html2text($post->text).qq{

Here's a link to that page: 
    http://mypleasanthillchurch.org$ENV{SCRIPT_NAME}/$section_name/$folder_name/$fake_it
    
Cheers!};
			#
		AppCore::Web::Common->send_email(['jbryan@productiveconcepts.com','pastor@mypleasanthillchurch.org'],"[PHC FORUMS] New Post Added to Forum '".$board->title."'",$email_body);
	}
	
	sub forum_page
	{
		my $class = shift;
		my ($section_name,$folder_name,$skin,$r,$page,$args,$path) = @_;
		
		
		my $board = PHC::WebBoard->by_field(folder_name => $folder_name);
		if(!$board)
		{
			return $skin->error("No Such Bulletin Board","Sorry, the folder or action name you gave did not match any existing Bulletin Board folders. Please check your URL or the link on the page that you clicked and try again.");
		}
		
		my $controller = $class;
		
		#die $board->folder_name;
		if($board->forum_controller)
		{
			eval 'use '.$board->forum_controller;
			if($@)
			{
				die $@;
			}
			
			$controller = $board->forum_controller;
		}

		
		my $sub_page = shift @$path;
		
		#$tmpl->param(can_upload=>1) if ($_ = AppCore::Common->context->user) && $_->check_acl($UPLOAD_ACL);
		
		my $bin = AppCore::Common->context->http_bin;
		
		if($sub_page eq 'post')
		{
			my $post = $controller->create_new_thread($board,$args);
			
			$controller->email_new_post($post,$section_name,$folder_name);
			$r->redirect(AppCore::Common->context->http_bin."/$section_name/$folder_name#c$post");
		}
		elsif($sub_page eq 'new')
		{
			my $tmpl = $skin->load_template($controller->config->{new_post_tmpl} || 'pages/boards/new_post.tmpl');
			$tmpl->param(pageid => $section_name);
			$tmpl->param(board_nav => $controller->macro_board_nav());
			$tmpl->param('board_'.$_ => $board->get($_)) foreach $board->columns;
			$tmpl->param('folder_'.$folder_name => 1);
			$tmpl->param(short_noun => $controller->config->{short_noun} || 'Boards');
			$tmpl->param(long_noun  => $controller->config->{long_noun}  || 'Bulletin Boards');
			
			
			$tmpl->param(post_url => AppCore::Common->context->http_bin."/$section_name/$folder_name/post");
			
			
			#die $controller;
			$controller->new_post_hook($tmpl,$board);
			
			return $r->output($tmpl);
		}
		elsif($sub_page eq 'print_list')
		{
			my $can_admin = 1 if ($_ = AppCore::Common->context->user) && $_->check_acl($controller->config->{admin_acl});
			
			
			my $tmpl = $skin->load_template($controller->config->{print_list_tmpl} || 'pages/boards/print_list.tmpl');
			$tmpl->param(pageid => $section_name);
			$tmpl->param(board_nav => $controller->macro_board_nav());
			$tmpl->param('board_'.$_ => $board->get($_)) foreach $board->columns;
			$tmpl->param('folder_'.$folder_name => 1);
			$tmpl->param(short_noun => $controller->config->{short_noun} || 'Boards');
			$tmpl->param(long_noun  => $controller->config->{long_noun}  || 'Bulletin Boards');
			
			my @id_list = split /,/, $args->{id_list};
			
			my @posts = map { PHC::WebBoard::Post->retrieve($_) } @id_list;
			
			my @output_list = map { $class->load_post($_,$section_name,$board->folder_name,1) } @posts;
			foreach my $b (@output_list)
			{
				$b->{bin} = $bin;
				$b->{pageid} = $section_name;
				$b->{folder_name} = $folder_name;
				$b->{can_admin} = $can_admin;
				
			}
			
			$tmpl->param(post_list => \@output_list);
			
			return $r->output($tmpl);
		}
		elsif($sub_page eq 'delete_list')
		{
			my $can_admin = 1 if ($_ = AppCore::Common->context->user) && $_->check_acl($controller->config->{admin_acl});
			
			die "Access denied - you're not an admin" if !$can_admin;
			
			my @id_list = split /,/, $args->{id_list};
			
			my @posts = map { PHC::WebBoard::Post->retrieve($_) } @id_list;
			
			foreach my $post (@posts)
			{
				$post->deleted(1);
				$post->update;
			}
			
			
			return $r->redirect("$bin/$section_name/$folder_name");
			
		}
		elsif($sub_page)
		{
			shift;shift;
			return $controller->post_page($section_name,$sub_page,$folder_name,@_);
		}
		else
		{
			
			my $tmpl = $skin->load_template($controller->config->{list_tmpl} || 'pages/boards/list.tmpl');
			$tmpl->param(pageid => $section_name);
			$tmpl->param(board_nav => $controller->macro_board_nav());
			$tmpl->param('board_'.$_ => $board->get($_)) foreach $board->columns;
			my $can_admin = 1 if ($_ = AppCore::Common->context->user) && $_->check_acl($controller->config->{admin_acl});
			$tmpl->param(can_admin=>$can_admin);
			
			
			my @posts = PHC::WebBoard::Post->search(deleted=>0,boardid=>$board,top_commentid=>0);
			@posts = sort {$b->timestamp cmp $a->timestamp} @posts;
			
			my $short_len = 60;
			my $last_post_subject_len = 20;
			foreach my $b (@posts)
			{
				$b->{$_} = $b->get($_) foreach $b->columns;
				$b->{bin} = $bin;
				$b->{pageid} = $section_name;
				$b->{folder_name} = $folder_name;
				$b->{can_admin} = $can_admin;
				$b->{short_text} = AppCore::Web::Common->html2text($b->{text});
				$b->{short_text} = substr($b->{short_text},0,$short_len) . (length($b->{short_text}) > $short_len ? '...' : '');
				
				my $lc = $b->last_commentid;
				if($lc && $lc->id && !$lc->deleted)
				{
					$b->{'post_'.$_} = $lc->get($_) foreach $lc->columns;
					$b->{post_subject} = substr($b->{post_subject},0,$last_post_subject_len) . (length($b->{post_subject}) > $last_post_subject_len ? '...' : '');
					$b->{post_url} = "$bin/$section_name/$folder_name/$b->{fake_folder_name}#c$lc";
				}
				
				$b->{text} = PHC::VerseLookup->tag_verses($b->{text});
				
				$controller->forum_list_hook($b);
			}
			
			#die Dumper \@posts;
			
			$tmpl->param(posts=>\@posts);
			
			$controller->forum_page_hook($tmpl,$board);
			
			return $r->output($tmpl);
		}
	}
	
	
	# This allows subclasses to hook into the list prep above without subclassing the entire list action
	sub forum_list_hook#($post)
	{}
	sub forum_page_hook#($tmpl,$board)
	{}
	
	sub new_post_hook#($tmpl,$board)
	{}
	
	sub main_page
	{
		my $class = shift;
		my ($skin,$r,$page,$args,$path) = @_;
		
		$r->header('X-Page-Comments-Disabled' => 1);
		
		my $section_name = $page;
		
		my $sub_page = shift @$path;
		
		my $bin = AppCore::Common->context->http_bin;
		
		if($sub_page eq 'new')
		{
			PHC::User::Auth->require_authentication($class->config->{admin_acl});
			my $tmpl = $skin->load_template($class->config->{edit_forum_tmpl} || 'pages/boards/edit_forum.tmpl');
			$tmpl->param(pageid => $section_name);
			$tmpl->param(post_url => AppCore::Common->context->http_bin."/$section_name/post");
			$tmpl->param(board_nav => $class->macro_board_nav());
			
			$tmpl->param(short_noun => $class->config->{short_noun} || 'Boards');
			$tmpl->param(long_noun  => $class->config->{long_noun}  || 'Bulletin Boards');
			
			
			my $group = PHC::WebBoard::Group->retrieve($args->{groupid});
			$skin->error("Invalid GroupID","Invalid GroupID") if !$group;
			$tmpl->param('group_'.$_ => $group->get($_)) foreach $group->columns;
			
			$class->board_settings_new_hook($tmpl) if $class->can('board_settings_new_hook');
			
			return $r->output($tmpl);
		}
		elsif($sub_page eq 'edit')
		{
			PHC::User::Auth->require_authentication($class->config->{admin_acl});
			my $tmpl = $skin->load_template($class->config->{edit_forum_tmpl} || 'pages/boards/edit_forum.tmpl');
			$tmpl->param(pageid => $section_name);
			$tmpl->param(post_url => AppCore::Common->context->http_bin."/$section_name/post");
			$tmpl->param(board_nav => $class->macro_board_nav());
			
			#my $config = $class->config;
			#print STDERR Dumper $config;
			
			$tmpl->param(short_noun => $class->config->{short_noun} || 'Boards');
			$tmpl->param(long_noun  => $class->config->{long_noun}  || 'Bulletin Boards');
			
			my $board = PHC::WebBoard->retrieve($args->{boardid});
			$skin->error("Invalid BoardID","Invalid BoardID") if !$board;
			my $group = $board->groupid;
			$tmpl->param('board_'.$_ => $board->get($_)) foreach $board->columns;
			$tmpl->param('group_'.$_ => $group->get($_)) foreach $group->columns;
			
			$class->board_settings_edit_hook($board,$tmpl) if $class->can('board_settings_edit_hook');
			
			return $r->output($tmpl);
		}
		elsif($sub_page eq 'post')
		{
			PHC::User::Auth->require_authentication($class->config->{admin_acl});
			my $board;
			if($args->{boardid})
			{
				$board = PHC::WebBoard->retrieve($args->{boardid});
			}
			else
			{
				$board = PHC::WebBoard->create({groupid => $args->{groupid},section_name=>$section_name});
			}
			
			$class->board_settings_save_hook($board,$args) if $class->can('board_settings_save_hook');
			
			foreach my $key (qw/folder_name title tagline sort_key/)
			{
				$board->set($key, $args->{$key});
			}
			
			
			$board->update;
			
			
			$r->redirect(AppCore::Common->context->http_bin."/$section_name"); 
		}
		elsif($sub_page eq 'feed.xml' || $sub_page eq 'rss')
		{
			my $tmpl = $class->rss_feed('',$args->{include_comments});
		
			$r->content_type('text/xml');
			$r->body($tmpl->output);
			return;
		}
		elsif($sub_page)
		{
			return $class->forum_page($section_name,$sub_page,@_);
		}
		else
		{
			my $tmpl = $skin->load_template($class->config->{main_tmpl} || 'pages/boards/main.tmpl');
			$tmpl->param(pageid => $section_name);
			$tmpl->param(board_nav => $class->macro_board_nav());
			my $can_admin = 1 if ($_ = AppCore::Common->context->user) && $_->check_acl($class->config->{admin_acl});;
			$tmpl->param(can_admin=>$can_admin);
		
		
			
			my @groups = PHC::WebBoard::Group->search(hidden=>0);
			@groups = sort {$a->sort_key cmp $b->sort_key} @groups;
			
			foreach my $g (@groups)
			{
				$g->{$_} = $g->get($_) foreach $g->columns;
				$g->{bin} = $bin;
				$b->{pageid} = $section_name;
				
				my @boards = PHC::WebBoard->search(groupid=>$g);
				@boards = sort {$a->sort_key cmp $b->sort_key} @boards;
				foreach my $b (@boards)
				{
					$b->{$_} = $b->get($_) foreach $b->columns;
					$b->{bin} = $bin;
					$b->{pageid} = $section_name;
					$b->{can_admin} = $can_admin;
					
					my $lc = $b->last_commentid;
					if($lc && $lc->id && !$lc->deleted)
					{
						$b->{'post_'.$_} = $lc->get($_) foreach $lc->columns;
						$b->{post_url} = "$bin/$section_name/$b->{folder_name}/".$lc->top_commentid->fake_folder_name."#c$lc" if $lc->top_commentid;
					}
				}
				
				$g->{can_admin} = $can_admin;
				$g->{boards} = \@boards;
			}
			#$tmpl->param(sermons => \@sermons);
			$tmpl->param(groups => \@groups);
			
			$r->html_header('link' => 
			{
				rel	=> 'alternate',
				title	=> 'Pleasant Hill Church RSS',
				href 	=> 'http://www.mypleasanthillchurch.org'.$bin.'/boards/rss',
				type	=> 'application/rss+xml'
			});
			$r->output($tmpl);
		}
	}
	
	sub rss_feed
	{
		my $class = shift;
		my $section = shift || undef;
		my $inc_comments = shift || 0;
		
		my $section_filter = '1';
		if($section)
		{
			my @boards = PHC::WebBoard->search(section_name => $section);
			die "No such section" if !@boards;
			$section_filter = 'boardid in ('.join(',',map{$_->id} @boards).')';
		}

		my $cmt_filter = $inc_comments ? '1' : '(parent_commentid = 0 or parent_commentid is NULL)';
		
		my $tmpl = PHC::Web::Skin->load_template($class->config->{feed_tmpl} || 'pages/boards/feed.xml.tmpl');
			
		my $cur_dt = dt_date();
		
		my $xml = $cur_dt->datetime;
		$xml =~ s/\s/T/g;
		
		my $current = $cur_dt->datetime;
		my $last_hr = $cur_dt->subtract(hours => 1);
		
		$tmpl->param(xml_datetime => $xml);
		my @recent = PHC::WebBoard::Post->retrieve_from_sql($section_filter.' and '.$cmt_filter.' and deleted=0 and hidden=0 and timestamp > "$last_hr" and timestamp < "$current" order by timestamp desc');
		if(!@recent)
		{
			@recent = PHC::WebBoard::Post->retrieve_from_sql($section_filter.' and '.$cmt_filter.' and deleted=0 and hidden=0 order by timestamp desc limit 0, 50');
		}
		
		my $bin = AppCore::Common->context->http_bin;
		foreach my $post (@recent)
		{
			$post->{$_} = $post->get($_) foreach $post->columns;
			$post->{folder_name}  = $post->boardid->folder_name;
			$post->{section_name} = $post->boardid->section_name;
			$post->{bin} = $bin;
			$post->{xml_timestamp} = $post->timestamp;
			$post->{xml_timestamp} =~ s/\s/T/g;
			$class->rss_filter_list_hook($post);
		}
		
		
		
		$tmpl->param(rdf_items => \@recent);
		
		return $tmpl;
			
	}
	
	sub rss_filter_list_hook {}
	
	sub news_ticker
	{
		my $class = shift;
		
		
		my $cur_dt = dt_date();
				
		my $xml = $cur_dt->datetime;
		$xml =~ s/\s/T/g;

		my $current = $cur_dt->datetime;
		my $last_hr = $cur_dt->subtract(hours => 1);

		my $timediff = "unix_timestamp() - unix_timestamp";
		
		#$tmpl->param(xml_datetime => $xml);
		
		#my @list = PHC::WebBoard::Post->retrieve_from_sql(qq{
		#				
		#		deleted=0  and hidden=0 
		#		
		#		order by ticker_priority asc, timestamp desc
		#		
		#		limit 0, 25
		#	
		#	});
		#}
		
		my $sth = PHC::WebBoard::Post->db_Main->prepare(qq{
				select p.postid, 
					p.boardid,
					p.poster_name,
					p.timestamp,
					unix_timestamp() - unix_timestamp(p.timestamp) as timediff,
					p.subject,
					p.text,
					p.fake_folder_name,
					p.ticker_class,
					boards.folder_name,
					boards.section_name,
					boards.title as `board_title`
					
				from board_posts p, boards 
				
				where p.deleted=0 and p.hidden=0 and
				      p.boardid = boards.boardid and
				      unix_timestamp() - unix_timestamp(p.timestamp) < ?
				
				order by ticker_priority desc, timestamp desc
				
				limit 0, 25
			
			});
		
		# 2 days
		my $range = 2 * 60 * 60 * 24;

		my $bin = AppCore::Common->context->http_bin;
		my $short_len = 35;
		my $subject_len = 20;
		my $board_len = 15;
		my @list;
		
		$sth->execute($range);
		#if(!$sth->rows)
		#{
		#	$sth->finish;
		#	$range = 7 * 60 * 60 * 24;
		#	$sth->execute($range);
		#}
		
		while(my $post = $sth->fetchrow_hashref)
		{
			$post->{sth}			= $sth;
			$post->{bin} 			= $bin;
			$post->{short_text} 		= AppCore::Web::Common->html2text($post->{text});
			$post->{short_text} 		= encode_entities(substr($post->{short_text},0,$short_len) . (length($post->{short_text}) > $short_len ? '...' : ''));
			$post->{'section_'.$post->{section_name}} = 1;
			$post->{'folder_'.$post->{folder_name}} = 1;
			$post->{'ticker_class_'.$post->{ticker_class}} = 1;
			$post->{board_title_short}	= substr($post->{board_title},0,$board_len) . (length($post->{board_title}) > $board_len ? '...' : '');
			$post->{board_title} 		= encode_entities($post->{board_title});
			$post->{subject_short}		= encode_entities(substr($post->{subject},0,$subject_len) . (length($post->{subject}) > $subject_len ? '...' : ''));
			$post->{subject} 		= encode_entities($post->{subject});
			$post->{min_ago}		= $post->{timediff} / 60;
			$post->{approx_hrs_ago}		= int($post->{min_ago} / 60);
			$post->{time_ago} 		= to_delta_string($post->{min_ago});

			$class->rss_filter_list_hook($post);
			
			push @list, $post;
		}
		
		return \@list;
	}
	

	__PACKAGE__->init_config();
}

1;
