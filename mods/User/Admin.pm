use strict;
package User::Admin;
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
	/);


	sub new { bless {}, shift }
	
	sub main
	{
		AppCore::AuthUtil->require_auth(['ADMIN']);
		
		my ($self,$req) = @_;
		my $r = AppCore::Web::Result->new;
		
		#my $view = AppCore::User::Controller->get_view('admin',$r);
		
		#die Dumper $req;
		
		my $tmpl = $self->get_template('list.tmpl');
		my $binpath = $self->binpath;
		my $modpath = $self->modpath;
		my $appcore = join('/', $AppCore::Config::WWW_ROOT);
		
		my @pages = AppCore::User->retrieve_from_sql('1 order by first, last');
		
		use Data::Dumper;
		
		my @cols = AppCore::User->columns;
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
		
		my ($self,$req) = @_;
		my $r = AppCore::Web::Result->new;
		#return $r->error("TBD - Create","TBD - Create: ".$self->module_url($CREATE_ACTION)." or tmpl: ".$self->get_template('create.tmpl'));
		
		#my $view = AppCore::User::Controller->get_view('admin',$r);
		
		my $tmpl = $self->get_template('edit.tmpl');
		
		my $url_from = AppCore::Web::Common->url_encode(AppCore::Web::Common->url_decode($req->{url_from}) || $ENV{HTTP_REFERER});
		$tmpl->param(url_from => $url_from);
		
		#$view->output($tmpl);
		return $r->output($tmpl);
	
		#return $r;
	}
	
	sub edit
	{
		AppCore::AuthUtil->require_auth(['ADMIN']);
		
		my ($self,$req) = @_;
		my $r = AppCore::Web::Result->new;
		#return $r->error("TBD - Create","TBD - Create: ".$self->module_url($CREATE_ACTION)." or tmpl: ".$self->get_template('create.tmpl'));
		
		#my $view = AppCore::User::Controller->get_view('admin',$r);
		
		my $user = $req->user;
		$user = $req->userid if !$user;
		
		my $obj = AppCore::User->retrieve($user);
		$obj = AppCore::User->by_field(user=>$user) if !$obj;
		if(!$obj)
		{
			return $r->redirect($self->module_url($CREATE_ACTION));
		}
		
		my $tmpl = $self->get_template('edit.tmpl');
		$tmpl->param(userid => $obj->id);
		
		$tmpl->param($_ => $obj->get($_)) foreach $obj->columns;
		
		my $url_from = AppCore::Web::Common->url_encode(AppCore::Web::Common->url_decode($req->{url_from}) || $ENV{HTTP_REFERER});
		$tmpl->param(url_from => $url_from);
		
		#$view->output($tmpl);
		return $r->output($tmpl);
	
		#return $r;
	}
	
	sub delete
	{
		AppCore::AuthUtil->require_auth(['ADMIN']);
		
		my ($self,$req) = @_;
		my $r = AppCore::Web::Result->new;
		
		my $id = $req->userid;
		
		my $obj = AppCore::User->retrieve($id);
		if(!$obj)
		{
			return $r->error("No such user","No such user: <b>$id</b>");
		}
		
		$obj->delete;
		
		return $r->redirect($self->module_url());
	}
	
	sub save
	{
		AppCore::AuthUtil->require_auth(['ADMIN']);
		
		my ($self,$req) = @_;
		my $r = AppCore::Web::Result->new;
		
		#use Data::Dumper;
		#print STDERR Dumper $req;
		
		my $userid = $req->userid;
		
		my $obj = $userid ? AppCore::User->retrieve($userid) : undef;
		
		if(!$obj)
		{
			$obj = AppCore::User->insert({
				user	=> $req->user 
			});
			print STDERR "Admin: Created userid $obj\n";
			$userid = $obj->id;
		}
		
		#print STDERR "Dump of req: ".Dumper($req);
		foreach my $col ($obj->columns)
		{
			#print STDERR "Checking col: $col\n";
			next if $col eq $obj->get_class_primary;
			$obj->set($col, $req->$col) if defined $req->$col;
		}
		
		$obj->update;
		
		print STDERR "Admin: Updated user $userid\n";
		
		my $url_from = AppCore::Web::Common->url_decode($req->{url_from});
		
		return $r->redirect($url_from ? $url_from : $self->module_url());
	}
	
};
1;
