use strict;
package Content::Admin;
{
	use AppCore::Web::Common;
	use base 'AppCore::Web::Module';

	my $PAGE_CREATE_ACTION = 'create';
	my $PAGE_EDIT_ACTION = 'edit';
	my $PAGE_DELETE_ACTION = 'delete';
	my $PAGE_SAVE_ACTION = 'save';
	
	__PACKAGE__->WebMethods(qw/ 
		main
		create
		edit
		delete
		save
		set_in_menus
		change_idx
	/);


	sub new { bless {}, shift }
	
	sub main
	{
		AppCore::AuthUtil->require_auth(['ADMIN']);
		
		my ($self,$req) = @_;
		my $r = AppCore::Web::Result->new;
		
		my $view = Content::Page::Controller->get_view('admin',$r);
		
		my $tmpl = $self->get_template('list.tmpl');
		my $binpath = $tmpl->param('binpath');
		
		my @pages = Content::Page->retrieve_from_sql('1 order by menu_index, url');
		
		use Data::Dumper;
		
		my @cols = Content::Page->columns;
		my @list;
		my $idx_cnt = 0;
		foreach my $page (@pages)
		{
			my $row = {};
			$row->{$_} = $page->get($_) foreach @cols;
			$row->{binpath} = $binpath;
			
			my @url = split /\//, $row->{url};
			shift @url;
			push @url, "<b>". pop(@url). "</b>";
			if(@url == 1)
			{
				$url[0] = "<span class='toplevel'>" . $url[0] . "</span>";
			}
			
			$row->{url_pretty} = '<span class=util>/</span>' . join('<span class=util>/</span>', @url); 
			$row->{in_menus} = $row->{show_in_menus} ? '<b>Yes</b>' : 'No';
			
			if(!$page->menu_index)
			{
				$row->{menu_index} = $idx_cnt ++;
				$page->menu_index($row->{menu_index});
				$page->update;
			}
			
			#die Dumper $row;
			push @list, $row;
		}
		
		$tmpl->param(pages => \@list);
		#die Dumper \@pages;
		
		$view->output($tmpl);
		return $r;
		
		
	};
	
	sub create
	{
		AppCore::AuthUtil->require_auth(['ADMIN']);
		
		my ($self,$req) = @_;
		my $r = AppCore::Web::Result->new;
		#return $r->error("TBD - Create","TBD - Create: ".$self->module_url($PAGE_CREATE_ACTION)." or tmpl: ".$self->get_template('create.tmpl'));
		
		my $view = Content::Page::Controller->get_view('admin',$r);
		
		my $url = $req->url;
		$url =~ s/^\///;
		
		my $tmpl = $self->get_template('create.tmpl');
		$tmpl->param(page_url => $url);
		
		$tmpl->param(page_title => AppCore::Common::guess_title($url));
		$tmpl->param(page_content => '');
		$tmpl->param(server_name => $AppCore::Config::WEBSITE_SERVER);
		
		my $url_from = AppCore::Web::Common->url_encode(AppCore::Web::Common->url_decode($req->{url_from}) || $ENV{HTTP_REFERER});
		$tmpl->param(url_from => $url_from);
		
		$view->output($tmpl);
	
		return $r;
		
	}
	
	sub edit
	{
		AppCore::AuthUtil->require_auth(['ADMIN']);
		
		my ($self,$req) = @_;
		my $r = AppCore::Web::Result->new;
		#return $r->error("TBD - Create","TBD - Create: ".$self->module_url($PAGE_CREATE_ACTION)." or tmpl: ".$self->get_template('create.tmpl'));
		
		my $view = Content::Page::Controller->get_view('admin',$r);
		
		my $url = $req->url;
		$url = '/' if !$url;
		
		my $page_obj = Content::Page->by_field(url => $url);
		if(!$page_obj)
		{
			return $r->redirect( $self->module_url($PAGE_CREATE_ACTION) . '?url='. $url);
		}
		
		$url =~ s/^\///;
		
		my $tmpl = $self->get_template('create.tmpl');
		$tmpl->param(page_url => $url);
		$tmpl->param(pageid => $page_obj->id);
		
		$tmpl->param(page_title   => $page_obj->title);
		$tmpl->param(page_content => $page_obj->content);
		$tmpl->param(server_name  => $AppCore::Config::WEBSITE_SERVER);
		
		my $url_from = AppCore::Web::Common->url_encode(AppCore::Web::Common->url_decode($req->{url_from}) || $ENV{HTTP_REFERER});
		$tmpl->param(url_from => $url_from);
		
		$view->output($tmpl);
	
		return $r;
	}
	
	sub delete
	{
		AppCore::AuthUtil->require_auth(['ADMIN']);
		
		my ($self,$req) = @_;
		my $r = AppCore::Web::Result->new;
		
		my $url = $req->url;
		
		my $page_obj = Content::Page->by_field(url => $url);
		if(!$page_obj)
		{
			return $r->error("No such page","No such page: <b>$url</b>");
		}
		
		$page_obj->delete;
		
		return $r->redirect($self->module_url());
	}
	
	sub set_in_menus
	{
		AppCore::AuthUtil->require_auth(['ADMIN']);
		
		my ($self,$req) = @_;
		my $r = AppCore::Web::Result->new;
		
		my $url = $req->url;
		
		my $page_obj = Content::Page->by_field(url => $url);
		if(!$page_obj)
		{
			return $r->error("No such page","No such page: <b>$url</b>");
		}
		
		$page_obj->show_in_menus($req->flag);
		$page_obj->update;
		
		if($req->quiet)
		{
			return $r->output_data('text/plain','Thanks for all the fish');
		}
		else
		{
			return $r->redirect($self->module_url());
		}
	}
	
	sub _renumber_page
	{
		my $self = shift;
		my $page_obj = shift;
		my $new_num = shift;
		
		my $old_idx = $page_obj->menu_index;
		$page_obj->menu_index($new_num);
		$page_obj->update;
		
		my $sth = Content::Page->db_Main->prepare('select pageid from pages where url like ?');
		$sth->execute($page_obj->url.'/%');
		
		while(my $ref = $sth->fetchrow_hashref)
		{
			my $child = Content::Page->retrieve($ref->{pageid});
			
			my $child_idx = $child->menu_index;
			$child_idx =~ s/^$old_idx/$new_num/;
			
			$child->menu_index($child_idx);
			$child->update;
		}
	}
	
	sub change_idx
	{
		AppCore::AuthUtil->require_auth(['ADMIN']);
		
		my ($self,$req) = @_;
		my $r = AppCore::Web::Result->new;
		
		my $url = $req->url;
		
		my $page_obj = Content::Page->by_field(url => $url);
		if(!$page_obj)
		{
			return $r->error("No such page","No such page: <b>$url</b>");
		}
		
		my $dir = $req->dir eq 'up' ? -1 : 1;
		
		my @url_parts = split /\//, $page_obj->url;
		
		# Get current idx and split at the dots
		_RECALC_IDX:
		my $idx = $page_obj->menu_index; 
		my @number_parts = split /\./, $idx;
		
		my @url_base = @url_parts;
		pop @url_base;
		my $url_base = join('/', @url_base);
		
		
		if(scalar(@number_parts) != scalar(@url_parts)-1)
		{
			#print STDERR "$url: Corrupt debug: ".Dumper(\@number_parts, \@url_parts)."\n";
			# Index corrupt, rebuild all sibling indexes
			my $sth = Content::Page->db_Main->prepare('select pageid from pages where url like ?');
			$sth->execute($url_base . '/%');
			
			# Must have parent to get the starting index
			my $parent = Content::Page->by_field(url => $url_base);
			if(!$parent)
			{
				die "Menu index for url '$url' corrupt, but could not find parent '$url_base' to use for rebuild";
			}
			my $parent_idx = $parent->menu_index;
			print STDERR "$url: Index corrupt, rebuilding based on parent '".$parent->url.", index: $parent_idx \n";
			
			# Loop thru siblings and just increment the index counter
			my $counter = 0;
			while(my $ref = $sth->fetchrow_hashref)
			{
				my $sib = Content::Page->retrieve($ref->{pageid});
				$sib->menu_index($parent_idx .'.'. $counter ++);
				$sib->update;
				print STDERR "$url: Rebuild: Sib ".$sib->url.", new index: ".$sib->menu_index."\n";
			}
			
			goto _RECALC_IDX;
		}
		
		# Get the current integer for this level of the page (last part of the number)
		my $cur_num = pop @number_parts;
		
		# Add/subtract one from the current integer
		my $new_num = $dir < 0 ? $cur_num - 1 : $cur_num + 1;
		$new_num = 1 if $new_num < 1;
		
		# Find the number of sibling pages to this page 
		my $sth = Content::Page->db_Main->prepare('select count(pageid) as count from pages where url like ?');
		$sth->execute($url_base . '/%');
		
		# Cap the integer for this page at the number of sibling pages
		my $count = $sth->rows ? $sth->fetchrow_hashref->{count} : 0;
		$new_num = $count if $new_num > $count;
		
		# Push the new integer onto the string of integers
		push @number_parts, $new_num;
		
		# Rejoin numbers with dots to form the new menu index
		my $new_idx = join '.', @number_parts;
		
		print STDERR "$url: new_idx: '$new_idx'\n";
		if($new_idx ne $idx)
		{
			my $existing_obj = Content::Page->by_field(menu_index => $new_idx);
			
			$self->_renumber_page($page_obj, $new_idx);
			$self->_renumber_page($existing_obj, $idx) if $existing_obj;
		}
			
		if($req->quiet)
		{
			return $r->output_data('text/plain','Thanks for all the fish');
		}
		else
		{
			return $r->redirect($self->module_url());
		}
	}
	
	sub save
	{
		AppCore::AuthUtil->require_auth(['ADMIN']);
		
		my ($self,$req) = @_;
		my $r = AppCore::Web::Result->new;
		
		#use Data::Dumper;
		#print STDERR Dumper $req;
		
		my $pageid  = $req->pageid;
		my $title   = $req->title;
		my $url     = '/' . $req->url;
		my $content = $req->content;
		
		my $page_obj = $pageid ? Content::Page->retrieve($pageid) : undef;
		
		if(!$page_obj)
		{
			my @url_parts = split /\//, $url;
		
			my @url_base = @url_parts;
			pop @url_base;
			my $url_base = join('/', @url_base);
			
			# Must have parent to get the starting index
			my $parent = Content::Page->by_field(url => $url_base);
			if(!$parent)
			{
				die "Must create the parent '$url_base' before creating '$url'";
			}
			my $parent_idx = $parent->menu_index;
			
			# Find the number of sibling pages to this page 
			my $sth = Content::Page->db_Main->prepare('select count(pageid) as count from pages where url like ?');
			$sth->execute($url_base . '/%');
		
			# Cap the integer for this page at the number of sibling pages
			my $count = $sth->rows ? $sth->fetchrow_hashref->{count} : 0;
			
			my $idx = $parent_idx . '.' . ($count+1);
			
			$page_obj = Content::Page->create({
				url	=>	$url, 
				typeid	=>	Content::Page::Type->by_field(view_code=>'sub'),
				show_in_menus	=> 1,
				menu_index	=> $idx
			});
			print STDERR "Admin: Created pageid $page_obj for url $url\n";
		}
		
		$page_obj->title($title);
		$page_obj->content($content);
		$page_obj->url($url);
		$page_obj->update;
		
		print STDERR "Admin: Updated pageid $pageid - \"$title\"\n";
		
		my $url_from = AppCore::Web::Common->url_decode($req->{url_from});
		
		return $r->redirect($url_from ? $url_from : $self->module_url());
	}
	
};
1;
