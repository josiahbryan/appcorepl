use strict;

package ThemePHC::AskPastor;
{
	# Inherit both the Boards and Page Controller.
	# We use the Page::Controller to register a custom
	# 'Board' page type for user-created board pages  
	use base qw{
		Boards
		Content::Page::Controller
	};
	
	# Register our pagetype
	__PACKAGE__->register_controller('PHC Ask Pastor','PHC Ask Pastor Controller',1,0);  # 1 = uses page path,  0 = doesnt use content
	

	use AppCore::EmailQueue;
	use AppCore::Web::Common;
	
	use Data::Dumper;
	use JSON qw/decode_json/;
	
	my $MGR_ACL = [qw/Pastor/];
	
	our $BOARD_FOLDER = 'ask_pastor';
	our $BOARD = Boards::Board->find_or_create(folder_name => $BOARD_FOLDER);
	
	my $SUBJECT_LENGTH = 30;
	
	sub new
	{
		my $class = shift;
		
		my $self = bless {}, $class;
		
		$self->config(); # setup default config
		$self->apply_config(
		{
			short_noun	=> 'Ask Pastor',
			long_noun	=> 'Ask the Pastor',
			
			admin_acl	=> [qw/Pastor/],
		});
		
		return $self;
	};
	
	# Implemented from Content::Page::Controller
	sub process_page
	{
		my $self = shift;
		my $type_dbobj = shift;
		my $req  = shift;
		my $r    = shift;
		my $page_obj = shift;
		
		# Change the 'location' of the webmodule so the webmodule code thinks its located at this page path
		# (but %%modpath%% will return /ThemeBryanBlogs for resources such as images)
		my $new_binpath = AppCore::Config->get("DISPATCHER_URL_PREFIX") . $req->page_path; # this should work...
		#print STDERR __PACKAGE__."->process_page: new binpath: '$new_binpath'\n";
		$self->binpath($new_binpath);
		
		## Redispatch thru the ::Module dispatcher which will handle calling main_page()
		#return $self->dispatch($req, $r);
		return $self->ask_pastor($req,$r);
		
# 		# Get a view module from the template based on view code so the template can choose to dispatch a view to a different object if needed
# 		my $view = $self->get_view($view_code,$r);
# 		
# 		# Pass the view code onto the view output function so that it can aggregate different view types into one module
# 		$view->output($page_obj,$r,$view_code);
	};
	
	
	
	
	# Overrides Boards::email_new_post_comment()
	sub email_new_comment
	{
		my $self = shift;
		my $post = shift;
		my $args = shift;
		
		my $server = AppCore::Config->get('WEBSITE_SERVER');
		
#		print STDERR __PACKAGE__."::email_new_post_comments(): Disabled till email is enabled\n";
# 			return;
		
		my $comment = $post;
		my $comment_url = $args->{comment_url} || $self->binpath ."/". $comment->boardid->folder_name . "/". $comment->top_commentid->folder_name."#c" . $comment->id;
		
		
		$comment_url =~ s/\/boards\//\/ask_pastor\//g;
		
		my $email_body = qq{A comment was added by }.$comment->poster_name." to '".$comment->top_commentid->subject.qq{':

    }.html2text($comment->text).qq{

Here's a link to that page: 
    http://mypleasanthillchurch.org${comment_url}
    
Cheers!};
		
		AppCore::EmailQueue->reset_was_emailed;
		
#		AppCore::EmailQueue->send_email(['josiahbryan@gmail.com'],"[PHC Ask Pastor] New Comment on QA: ".$comment->top_commentid->subject,$email_body);
		AppCore::EmailQueue->send_email(['josiahbryan@gmail.com','pastor@mypleasanthillchurch.org'],"[PHC Ask Pastor] New Comment on QA: ".$comment->top_commentid->subject,$email_body);
		AppCore::EmailQueue->send_email([$comment->parent_commentid->poster_email],
			"[PHC Ask Pastor] New Reply on QA: ".$comment->top_commentid->subject,$email_body)
				if $comment->parent_commentid && $comment->parent_commentid->id && $comment->parent_commentid->poster_email
				&& !AppCore::EmailQueue->was_emailed($comment->parent_commentid->poster_email);
		AppCore::EmailQueue->send_email([$comment->top_commentid->poster_email],
			"[PHC Ask Pastor] New Comment on QA: ".$comment->top_commentid->subject,$email_body)
				if $comment->top_commentid && $comment->top_commentid->id && $comment->top_commentid->poster_email 
				&& !AppCore::EmailQueue->was_emailed($comment->top_commentid->poster_email);
		
		AppCore::EmailQueue->reset_was_emailed;
		
		# A bit of a hack here. The function in Boards that calls us normally does
		# its own redirect - but I want to hijack the redirect here for myself so I cheat by using the 
		# singleton methods on PHC::Web::Skin to get the PHC::Web::Result object on which to do the redirect.
		AppCore::Web::Common->redirect($self->module_url("/ask_pastor#p".$comment->top_commentid));
	}
	
	# Overrides Boards::email_new_post()
	sub email_new_post
	{
	
		my $self = shift;
		my $post = shift;
		my $section_name = shift;
		my $folder_name = shift;
		
		my $fake_it = $post->folder_name;
		my $board = $post->boardid;
		
		my $email_body = qq{A new post was added by }.$post->poster_name." in forum '".$board->title.qq{':

    }.html2text($post->text).qq{

Here's a link to that page: 
    http://beta.mypleasanthillchurch.org/learn/ask_pastor/$folder_name
    
Cheers!};
			#
			#
		AppCore::EmailQueue->send_email(['josiahbryan@gmail.com','pastor@mypleasanthillchurch.org'],"[PHC Ask Pastor] New Question: ".$post->subject,$email_body);
#		AppCore::EmailQueue->send_email(['josiahbryan@gmail.com'],"[PHC Ask Pastor] New Question: ".$post->subject,$email_body);
	}
	
	
	sub ask_pastor
	{
		# Rework:
		# - need to flag it either as the Q (which would be the top post),or A (special attribute_data), or a general comment
		# - rewrite "post" page to remove subject, make subject be first 100 letters of textual body
		# - add special "reply" page for pastor which flags reply as the answer
		# - rewrite list template to display the Q and A 
		# - rewrite list screen to load the "A" reply seperate from regular comments (maybe set top_commentid to the question, oooooorrr...
		# store answer in attribute_data ????)
		
		# So, after writing that, heres what we need:
		# - rewrite current "new post" screen per above
		# - add special "answer question" screen for pastor, store answer in attributes
		# - rewrite list template/screen as above
	
		my $self = shift;
		
		#my ($skin,$r,$page,$req,$path) = @_;
		my ($req,$r) = @_;
		#print STDERR Dumper($path);
		
		my $view = Content::Page::Controller->get_view('sub',$r);
		$view->breadcrumb_list->push('Ask Pastor',$self->module_url(),0);
		
		
		# Shift off the name of the blog ('pastors_blog') since we are hardcoding it anyway (above, $BOARD_FOLDER)
		my $folder_name = ''; #$req->shift_path; #lc shift @$path;
		#my $section_name = $page;
		
		# Peek at the action so we can enforce ACLs, but dont shift, because we want the Boards controller to 
		# handle the action if there is any. (Empty action means the list screen, handeled here in this package, below.)
		my $action = $req->next_path; #lc $path->[0];
		
		#die Dumper [$folder_name,$action,$req];
		
		
		my $binpath = $self->binpath;
		
		my $can_admin = 1 if ($_ = AppCore::Common->context->user) && $_->check_acl($Boards::ADMIN_ACL);
		my $can_mgr   = 1 if ($_ = AppCore::Common->context->user) && $_->check_acl($MGR_ACL);
		
		my $board = $BOARD;
		
		if(!$action || $action =~ /^([\d+])$/)
		{
			$req->{questionid} = $1 if $action && ! $req->{questionid};
			
			# The primary changes from the "list" action in the Web::Boards controller is:
			# (a) - using a different template that formats the list differently
			# (b) Calling $self->load_post(...) and applying the returned result set to the row in the list,
			#     thereby creating a hybrid list and post viewer.
			# All other actions are routed through the Boards::forum_page() method.
			
			my $tmpl = $self->get_template('ask_pastor/list.tmpl');
			#$tmpl->param(pageid => $section_name);
			$tmpl->param(board_nav => $self->macro_board_nav());
			$tmpl->param('board_'.$_ => $board->get($_)) foreach $board->columns;
			
			$tmpl->param(can_admin=>$can_admin);
			$tmpl->param(can_mgr=>$can_mgr);
			
			
			my $user = AppCore::Common->context->user;
		
			my @posts = @{ $self->load_questions() || [] }; 
			
			my $found_post = 0;
			foreach my $b (@posts)
			{
				my $flag = $req->{questionid} ? $b->id == $req->{questionid} : ! $b->{answer};
				$b->{latest} = $flag;
				$found_post = 1 if $flag;
			}
			
			$posts[0]->{latest} = 1 if @posts && !$found_post;
			$tmpl->param(questionid => $req->{questionid});
			
			my $counter;
			$_->{odd} = ++ $counter % 2 == 0 foreach @posts;
			
			#die Dumper \@posts;
			
# 			$r->html_header('link' => 
# 			{
# 				rel	=> 'alternate',
# 				title	=> 'Pleasant Hill Church - Ask the Pastor RSS',
# 				href 	=> 'http://www.mypleasanthillchurch.org/learn/ask_pastor/rss',
# 				type	=> 'application/rss+xml'
# 			});
			
			$tmpl->param(posts=>\@posts);
			$tmpl->param(old_posts=>\@posts);
			#return $r->output($tmpl);
			#$view->breadcrumb_list->push('Ask Pastor',$self->module_url(),0);
			return $view->output($tmpl);
		}
		elsif($action eq 'edit_settings')
		{
			return $r->error("Not Allowed","You are not the administrator of this board.") if !$can_mgr;
			my $tmpl = $self->get_template('edit_forum.tmpl');
			#$tmpl->param(pageid 	=> $section_name);
			$tmpl->param(post_url 	=> "$binpath/save_settings");
			#$tmpl->param(board_nav 	=> $self->macro_board_nav());
			
			$tmpl->param('board_'.$_ => $board->get($_)) foreach $board->columns;
			
			
			my $group = $board->groupid;
			if($group && $group->id)
			{
				$tmpl->param('group_'.$_ => $group->get($_)) foreach $group->columns;
			}
			
			#return $r->output($tmpl);
			$view->breadcrumb_list->push('Edit Settings',$self->module_url(),0);
			return $view->output($tmpl);
		}
		elsif($action eq 'save_settings')
		{
			return $r->error("Not Allowed","You are not the administrator of this board.") if !$can_mgr;
			
			foreach my $key (qw/folder_name title tagline sort_key/)
			{
				$board->set($key, $req->{$key});
			}
			
			$board->update;
			
			$r->redirect("$binpath/$folder_name"); 
		}
		elsif($action eq 'new')
		{
			my $tmpl = $self->get_template('ask_pastor/new_qa.tmpl');
			#$tmpl->param(pageid => $section_name);
			$tmpl->param(board_nav => $self->macro_board_nav());
			$tmpl->param('board_'.$_ => $board->get($_)) foreach $board->columns;
			
			$tmpl->param(post_url => "$binpath/post");
			
			#return $r->output($tmpl);
			$view->breadcrumb_list->push('New Q&A',$self->module_url(),0);
			return $view->output($tmpl);
		}
		elsif($action eq 'post')
		{
			my $text = html2text($req->{age});
			$text =~ s/[\r\n]/ /g;
			
			$req->{subject} = substr($text,0,$SUBJECT_LENGTH). (length($text) > $SUBJECT_LENGTH ? '...' : '');
			
			my $post = $self->create_new_thread($board,$req);
			$self->notify_via_email('new_post',$post);
			$r->redirect($self->module_url("#p$post"));
		}
		elsif($action eq 'answer')
		{
			my $tmpl = $self->get_template('ask_pastor/answer_qa.tmpl');
			#$tmpl->param(pageid => $section_name);
			$tmpl->param(board_nav => $self->macro_board_nav());
			$tmpl->param('board_'.$_ => $board->get($_)) foreach $board->columns;
			
			my $post = Boards::Post->retrieve($req->{postid});
			return $r->error("Invalid Post#","Invalid Post#") if !$post;
			$tmpl->param('post_'.$_ => $post->get($_)) foreach $post->columns;
			#$tmpl->param(answer => $post->data->get('answer'));
			
			if(my $answer_postid = $post->data->get('answer_postid'))
			{
				my $ap = Boards::Post->retrieve($answer_postid);
				if($ap && $ap->id)
				{
					$tmpl->param(answer => $ap->text);
				}
				#die Dumper $b->{answer}, $answer_postid, $ap;
			}
			else
			{
				$tmpl->param(answer => $post->data->get('answer'));
			}
			
			$tmpl->param(post_url => "$binpath/save_answer");
			
			#return $r->output($tmpl);
			
			$view->breadcrumb_list->push('Answer Question',$self->module_url(),0);
			return $view->output($tmpl);
		}
		elsif($action eq 'save_answer')
		{
			# store in attributes and send email to original poster
			
			my $post = Boards::Post->retrieve($req->{postid});
			return $r->error("Invalid Post#","Invalid Post#") if !$post;
			
			if($post->data->get('answer_postid') || $post->data->get('answer'))
			{
				if($post->data->get('answer_postid'))
				{
					my $answer_post = Boards::Post->retrieve($post->data->get('answer_postid'));
					if(!$answer_post || !$answer_post->id)
					{
						$answer_post = $self->create_new_answer($board,$post,$req);
					}
					
					#die Dumper $answer_post;
					$answer_post->text($req->{comment});
					$answer_post->update;
				}
				else
				{
					$post->data->set('answer',$req->{comment});
					$post->data->update;
				}
			}
			else
			{
				$self->create_new_answer($board,$post,$req);
			}
			
			$r->redirect($self->module_url("#p$post"));
		}
		elsif($action eq 'feed.xml' || $action eq 'rss')
		{
			my $tmpl = $self->rss_feed(); #$section_name);
			$tmpl->param(feed_title => 'PHC Ask the Pastor Forum');
			$tmpl->param(feed_description => 'Pleasant Hill Church\'s &quot;Ask the Pastor&quot; forum with user-submitted questions to the pastor and discussions.');

			
			$r->content_type('text/xml');
			$r->body($tmpl->output);
			return;
		}
		else
		{
			# This line here only allows access to the pastors_blog through this URL, even though we are inheriting from Boards
			return $r->redirect($self->module_url('/'.$BOARD_FOLDER)) unless !$folder_name || $folder_name eq $BOARD_FOLDER; 
			
			return $self->board_page($req,$r,$BOARD);
		}	
	}
	
	
	our $DataCache = 0;
	sub clear_cached_dbobjects
	{
		#print STDERR __PACKAGE__.": Clearing cache...\n";
		$DataCache = 0;
	}	
	AppCore::DBI->add_cache_clear_hook(__PACKAGE__,'load_questions');
	
	sub load_questions
	{
		my $self = shift;
		
		my $posts = $DataCache;
		return $posts if $posts;
		
		# correct binpath if priming cache outside a HTTP call
		$self->binpath('/learn/ask_pastor') if $self->binpath =~ /themephc/;
			
		
		#print STDERR __PACKAGE__."->load_questions: Cache miss\n";
		
		my $can_admin = 1 if ($_ = AppCore::Common->context->user) && $_->check_acl($Boards::ADMIN_ACL);
		my $can_mgr   = 1 if ($_ = AppCore::Common->context->user) && $_->check_acl($MGR_ACL);
		
		my $board = $BOARD;
		
		#print STDERR __PACKAGE__."->load_questions: Board:'$board', folder: '$BOARD_FOLDER'\n";
		
		my $folder_name = $board->folder_name;
		my @posts = Boards::Post->search(deleted=>0,boardid=>$board,top_commentid=>0);
		@posts = sort {$b->timestamp cmp $a->timestamp} @posts;
		
		my $binpath = $self->binpath;
		
		my $short_len = 75;
		foreach my $b (@posts)
		{
			$b->{$_} = $b->get($_) foreach $b->columns;
			$b->{bin} = $binpath;
			#$b->{pageid} = $section_name;
			$b->{folder_name} = $folder_name;
			$b->{can_admin} = $can_admin;
			$b->{text} =~ s/<(\/)?pre.*?>/<$1p>/g;
			$b->{text} =~ s/<p>&nbsp;<\/p>//gi;
			$b->{short_text} = html2text($b->{text});
			#$b->{short_text} =~ s/<[^\>]+>//g;
			$b->{short_text} = substr($b->{short_text},0,$short_len) . (length($b->{short_text}) > $short_len ? '...' : '');
			
			my $lc = $b->last_commentid;
			if($lc && $lc->id)
			{
				$b->{'post_'.$_} = $lc->get($_) foreach $lc->columns;
				$b->{post_url} = $self->module_url("$b->{folder_name}#c$lc");
			}
			
			my @keys = keys %$b;
			#$b->{'post_'.$_} = $b->{$_} foreach @keys;
			#$b->{'board_folder_name'} = $BOARD_FOLDER;
			#($post,$req,$dont_count_view||0,$more_local_ctx||undef);
			#my $post_resultset = $self->load_post($b,undef,{can_reply=> $can_admin || $can_mgr || ($user && $user->id && $user->id == $b->posted_by) });
			my $post_resultset = $self->load_post($b,1); #,undef,{can_reply=> $can_admin || $can_mgr || ($user && $user->id && $user->id == $b->posted_by) });
			
			if(my $replies = $post_resultset->{replies})
			{
				# Filter out the 'answer' post
				$post_resultset->{replies} = [ grep { decode_json($_->{extra_data} ? $_->{extra_data} : '{}')->{is_answer} != 1 } @$replies ];
				
			}
			
			$b->{$_} = $post_resultset->{$_} foreach keys %$post_resultset;
			
			#$b->{text} = Boards::TextFilter::TagVerses->replace_block($b->{text});
			
			if(my $answer_postid = $b->data->get('answer_postid'))
			{
				my $ap = Boards::Post->retrieve($answer_postid);
				if($ap && $ap->id)
				{
					$b->{answer} = $ap->text;
				}
				#die Dumper $b->{answer}, $answer_postid, $ap;
			}
			else
			{
				$b->{answer} = $b->data->get('answer');
			}
			
			$b->{short_answer} = html2text($b->{answer});
			$b->{short_answer} = substr($b->{short_answer},0,$short_len) . (length($b->{short_answer}) > $short_len ? '...' : '');
			
			$b->{answer_timestamp} = $b->data->get('answer_timestamp');
			
			$b->{answer} = Boards::TextFilter::TagVerses->replace_block($b->{answer});
			#$b->{short_text} = Boards::TextFilter::TagVerses->replace_block($b->{short_text});
			$b->{short_answer} = Boards::TextFilter::TagVerses->replace_block($b->{short_answer});
			$b->{short_timestamp} = (split(/\s/,$b->{timestamp}))[0];
			
			$b->{can_mgr} = $can_mgr;
		}
		
		$DataCache = \@posts;
		return $DataCache;
	}
	
	sub create_new_answer
	{
		my $self = shift;
		my $board = shift;
		my $post  = shift;
		my $req  = shift;
		
		my $user = AppCore::Common->context->user;
		my $plain_text = html2text($req->{comment});
		
		my $create_args = {
			poster_name	=> $user->display,
			poster_email	=> $user->email,
			comment		=> $req->{comment}, 
			subject		=> substr($plain_text,0,$SUBJECT_LENGTH). (length($plain_text) > $SUBJECT_LENGTH ? '...' : ''),
		};
		
		#die Dumper $create_args;
		
		my $answer_post = $self->create_new_comment($board,$post,$create_args);
		
		$answer_post->data->set('is_answer',1);
		$answer_post->data->update;
		
		#$post->data->set('answer',$req->{comment});
		$post->data->set('answer_postid',$answer_post->id);
		$post->data->set('answer_timestamp',date());
		$post->data->update;
		
		#die "Created answer post: $answer_post, answer to question $post, text: ".$answer_post->text;
		
		my $binpath = $self->binpath;
		my $email_body = qq{The answer was posted to '"}.$post->subject.qq{':

    $plain_text

Here's a link to that page: 
    http://mypleasanthillchurch.org${binpath}#p$post
    
Cheers!};
		
		AppCore::EmailQueue->reset_was_emailed;
		
		AppCore::EmailQueue->send_email(['josiahbryan@gmail.com'],"[PHC Ask Pastor] Answer Posted to QA: ".$post->subject,$email_body);
		AppCore::EmailQueue->send_email([$post->poster_email],
			"[PHC Ask Pastor] Answer Posted to QA: ".$post->subject,$email_body)
				if $post->poster_email
				&& !AppCore::EmailQueue->was_emailed($post->poster_email);
		
		AppCore::EmailQueue->reset_was_emailed;
	}
	
};


1;
