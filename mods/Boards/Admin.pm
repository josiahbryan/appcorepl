use strict;
package Boards::Admin;
{
	use AppCore::Web::Common;
	use base 'AppCore::Web::Module';

	my $CREATE_ACTION = 'create';
	my $EDIT_ACTION   = 'edit';
	my $DELETE_ACTION = 'delete';
	my $SAVE_ACTION   = 'save';
	
	__PACKAGE__->WebMethods(qw/ 
		main
		create
		edit
		delete
		save
		fb_connector
	/);

	use JSON qw/decode_json/;

	sub new { bless {}, shift }

	#sub dispatch { die "foobar" }
	
	sub main
	{
		AppCore::AuthUtil->require_auth(['ADMIN']);
		
		my ($self,$req,$r) = @_;
		
		#my $view = AppCore::User::Controller->get_view('admin',$r);
		
		#die Dumper $req;
		
		my $tmpl = $self->get_template('list.tmpl');
		my $binpath = $self->binpath;
		my $modpath = $self->modpath;
		my $appcore = join('/', AppCore::Config->get("WWW_ROOT"));
		
		my @pages = Boards::Board->retrieve_from_sql('1 order by title'); #search(enabled => 1);
		
		use Data::Dumper;
		
		my @cols = Boards::Board->columns;
		my @list;
		foreach my $page (@pages)
		{
			my $row = {};
			$row->{$_} = $page->get($_) foreach @cols;
			$row->{binpath} = $binpath;
			$row->{modpath} = $modpath;
			$row->{appcore} = $appcore;
# 			$row->{tab_idx} = $tab_cnt++;
			
			#die Dumper $row;
			push @list, $row;
		}
		
		$tmpl->param(list => \@list);
		
		#$view->output($tmpl);
		$r->output($tmpl);
		return $r;
		
		
	};
	
	sub create
	{
		AppCore::AuthUtil->require_auth(['ADMIN']);
		
		my ($self,$req,$r) = @_;
		#return $r->error("TBD - Create","TBD - Create: ".$self->module_url($CREATE_ACTION)." or tmpl: ".$self->get_template('create.tmpl'));
		
		#my $view = AppCore::User::Controller->get_view('admin',$r);
		
		$req->{current_view}->breadcrumb_list->push('Create New Board',$self->module_url('create'),0);
		
		my $tmpl = $self->get_template('edit.tmpl');
		
		my $url_from = AppCore::Web::Common->url_encode(AppCore::Web::Common->url_decode($req->{url_from}) || $ENV{HTTP_REFERER});
		$tmpl->param(url_from => $url_from);
		$tmpl->param(users => AppCore::User->tmpl_select_list());
		#$view->output($tmpl);
		return $r->output($tmpl);
	
		#return $r;
	}
	
	sub edit
	{
		AppCore::AuthUtil->require_auth(['ADMIN']);
		
		my ($self,$req,$r) = @_;
		#return $r->error("TBD - Create","TBD - Create: ".$self->module_url($CREATE_ACTION)." or tmpl: ".$self->get_template('create.tmpl'));
		
		#my $view = AppCore::User::Controller->get_view('admin',$r);
		
		my $boardid = $req->boardid;
		
		my $obj = Boards::Board->retrieve($boardid);
		if(!$obj)
		{
			return $r->redirect($self->module_url($CREATE_ACTION));
		}
		
		$req->{current_view}->breadcrumb_list->push($obj->title,$self->module_url('edit?boardid='.$boardid),0);
		
		
		my $tmpl = $self->get_template('edit.tmpl');
		$tmpl->param($_ => $obj->get($_)) foreach $obj->columns;
		
		my $url_from = AppCore::Web::Common->url_encode(AppCore::Web::Common->url_decode($req->{url_from}) || $ENV{HTTP_REFERER});
		$tmpl->param(url_from => $url_from);
		$tmpl->param(users => AppCore::User->tmpl_select_list($obj->managerid));
		$tmpl->param(fb_app_id	  => AppCore::Config->get("FB_APP_ID"));
		$tmpl->param(fb_redir_url => $self->get_facebook_redir_url($boardid));
		
		#$view->output($tmpl);
		return $r->output($tmpl);
	
		#return $r;
	}
	
	sub get_facebook_redir_url
	{
		my $self = shift;
		my $boardid = shift;
		return $self->module_url('fb_connector/'.$boardid, 1); # 1 = incl server
	}
	
	sub fb_connector
	{
		my ($self, $req, $r) = @_;
		
		my $boardid = $req->next_path;
		if(!$boardid)
		{
			return $r->error("URL Error","No boardid in the path!");
		}
		
		if($req->{code})
		{
			# We're at step 1 - They've accepted us, now we have to get the access_token
			
			my $code = $req->code;
			print STDERR "Authenticated FB code $code, now requesting access_token\n";
				
			my $token_url = 'https://graph.facebook.com/oauth/access_token?'
				. 'client_id='     . AppCore::Config->get("FB_APP_ID")
				.'&redirect_uri='  . $self->get_facebook_redir_url($boardid)
				.'&client_secret=' . AppCore::Config->get("FB_APP_SECRET")
				.'&code=' . $code;
			
			my $response = LWP::Simple::get($token_url);
			
			my ($token) = $response =~ /access_token=(.*)$/;
			
			my $expires = '0000-00-00 00:00:00';
			if($token =~ /&expires=(\d+)$/)
			{
				$expires = $1;
				$token =~ s/&expires=\d+//g;
				
				my $dt = DateTime->now(); 
				$dt->add( seconds => $expires );
				
				$expires = $dt->datetime;
			}
			
			if($token)
			{
				my $accounts_url = 'https://graph.facebook.com/me/accounts?access_token='.$token;
				
				print STDERR "Accounts URL: $accounts_url\n";
				my $json = LWP::Simple::get($accounts_url);
				my $data;
				eval { $data = decode_json($json); };
				if($@)
				{
					return $r->error("Facebook API Error","Error parsing accounts data:<br><code>$@</code><br>Original data:<br><code>$json</code>");
				}
				
				if($data)
				{
					my $board = Boards::Board->retrieve($boardid);
					return $r->error("Facebook API Error","No boardid $boardid") if !$board;
					
					$req->{current_view}->breadcrumb_list->push($board->title,$self->module_url('edit?boardid='.$boardid),0);
					$req->{current_view}->breadcrumb_list->push('Choose FB Account',$self->module_url('fb_connector/'.$boardid),0);
			
					my $tmpl = $self->get_template('fb_account_choices.tmpl');
					$tmpl->param(page_list => $data->{data});
					$tmpl->param(my_token => $token);
					$tmpl->param(boardid => $boardid);
					$tmpl->param(title => $board->title);
					$tmpl->param(post_url => $self->get_facebook_redir_url($boardid));
					
					#my $view = Content::Page::Controller->get_view('admin',$r);
					#$view->output($tmpl);
					return $r->output($tmpl);
				}
				else
				{
					# Error getting user data, show error msg
					return $r->error("Facebook API Error","Problem getting accounts data:<br><code>$json</code>");
				}
			}
			else
			{
				# Error getting token, show error msg
				return $r->error("Facebook API Error","Problem getting access token - make sure \$FB_APP_ID and \$FB_APP_SECRET are correct in appcore/conf/appcore.conf.<br><code>$response</code>");
			}

			
		}
		elsif($req->{chosen_feed})
		{
			my $board = Boards::Board->retrieve($boardid);
			return $r->error("Facebook API Error","No boardid $boardid") if !$board;
			
			my ($name,$feed,$token) = $req->chosen_feed =~ /^([^\!]+)\!([^\!]+)\!(.*)/;
			return $r->error("Facebook API Error","Error parsing 'chosen_feed' parameter '".$req->chosen_feed."'") if !$feed || !$token;
			
			$board->fb_feed_name($name);
			$board->fb_feed_id($feed);
			$board->fb_access_token($token);
			$board->update;
			
			return $r->redirect($self->module_url('edit?boardid='.$boardid));
			
			
		}
		else
		{
			# Error getting code, show error msg
			return $r->error("Facebook API Error","No code and no feed_id - not sure what you want to do!");
		}
	}
	
	
	sub delete
	{
		AppCore::AuthUtil->require_auth(['ADMIN']);
		
		my ($self,$req,$r) = @_;
		
		my $id = $req->boardid;
		
		my $obj = Boards::Board->retrieve($id);
		if(!$obj)
		{
			return $r->error("No such board","No such board: <b>$id</b>");
		}
		
		$obj->delete;
		
		return $r->redirect($self->module_url());
	}
	
	sub save
	{
		AppCore::AuthUtil->require_auth(['ADMIN']);
		
		my ($self,$req,$r) = @_;
		
		#use Data::Dumper;
		#print STDERR Dumper $req;
		
		my $boardid = $req->boardid;
		
		my $obj = $boardid ? Boards::Board->retrieve($boardid) : undef;
		
		if(!$obj)
		{
			$obj = Boards::Board->insert({folder_name=>$req->folder_name});
			print STDERR "Admin: Created boardid $obj\n";
			$boardid = $obj->id;
		}
		
		#print STDERR "Dump of req: ".Dumper($req);
		foreach my $col (qw/title tagline description managerid folder_name sort_key hidden enabled fb_sync_enabled fb_feed_id fb_feed_name fb_access_token/ )
		{
			#print STDERR "Checking col: $col\n";
			#next if $col eq 'boardid';
			$obj->set($col, $req->{$col}); # if defined $req->$col;
		}
		
		$obj->fb_sync_enabled(0) if !$obj->fb_access_token;
		
		$obj->update;
		
		print STDERR "Admin: Updated board $boardid\n";
		
		my $url_from = AppCore::Web::Common->url_decode($req->{url_from});
		
		#return $r->redirect($url_from ? $url_from : $self->module_url());
		return $r->redirect($self->module_url());
	}
	
};
1;
