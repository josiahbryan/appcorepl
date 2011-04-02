# Package: Content::Page
# Base package for content pages
use strict;

package Content::Page;
{
	use base 'AppCore::DBI';
	
	__PACKAGE__->meta({
		class_noun	=> 'Page',
		class_title	=> 'Page Database',
		
		table		=> $AppCore::Config::PAGE_DBTABLE || 'pages',
		
		schema	=>
		[
			{
				'field'	=> 'pageid',
				'extra'	=> 'auto_increment',
				'type'	=> 'int(11)',
				'key'	=> 'PRI',
				readonly=> 1,
				auto	=> 1,
			},
			# Type is like a "Content-Type" for the page:
			# - Basic "Static" page 
			# - Custom types like a Blog app, News app, etc
			# Types can generate custom content or use the content in this object in some manner
			{	field	=> 'typeid',		type	=> 'int(11)',	linked => 'Content::Page::Type' },
			# The next page up in the nav structure
			{	field	=> 'parentid',		type	=> 'int(11)',	linked => 'Content::Page' },
			{	field	=> 'url',		type	=> 'varchar(255)' },
			{	field	=> 'title',		type	=> 'varchar(255)' },
			{	field	=> 'nav_title',		type	=> 'varchar(255)' },
			{	field	=> 'description',	type	=> 'varchar(255)' },
			{	field	=> 'teaser',		type	=> 'varchar(255)' },
			{	field	=> 'content',		type	=> 'text' },
			{	field	=> 'extended_data',	type	=> 'text' }, # JSON-encoded attributes for extra Page::Type storage

			
		]	
	
	});
	
	sub apply_mysql_schema
	{
		my $self = shift;
		$self->mysql_schema_update('Content::Page');	
		$self->mysql_schema_update('Content::Page::Type');
	}
};

package Content::Page::Type;
{
	use base 'AppCore::DBI';
	
	__PACKAGE__->meta({
		class_noun	=> 'Page Type',
		class_title	=> 'Page Type Database',
		
		table		=> $AppCore::Config::PAGETYPE_DBTABLE || 'page_types',
		
		schema	=>
		[
			{
				'field'	=> 'typeid',
				'extra'	=> 'auto_increment',
				'type'	=> 'int(11)',
				'key'	=> 'PRI',
				readonly=> 1,
				auto	=> 1,
			},
			{	field	=> 'name',		type	=> 'varchar(255)' },
			{	field	=> 'description',	type	=> 'varchar(255)' },
			{	field	=> 'controller',	type	=> 'varchar(255)' },
			{	field	=> 'view_code',		type	=> 'varchar(255)' },
		]
	
	});
	
	
	sub process_page
	{
		# Calls controller to do the real work
		my $self = shift;
		my $req  = shift;
		my $r    = shift;
		my $page_obj = shift;
		
		if($self->controller)
		{
			# Assume controller is loaded
			my $pkg = $self->controller;
			
			if($pkg == __PACKAGE__)
			{
				# They really meant to call the base class for types
				$pkg = 'Content::Page::Controller';
			}
			
			undef $@;
				
			eval
			{
				# Pass $self as the first arg so subclasses can access the ID of this type
				$pkg->process_page($self,$req,$r,$page_obj);
			};
			
			if($@)
			{
				$r->error("Error Outputting Page","The controller object '<i>$pkg</i>' had a problem processing your page:<br><pre>$@</pre>"); 
			}
		}
		else
		{
			failover_output($r,$page_obj);
		}
		
		return $r;
	}
	
	sub failover_output
	{
		shift if $_[0] eq __PACKAGE__;
		my $r = shift;
		my $page_obj = shift;
		$r->output($page_obj->content);
	}
};

package Content::Page::Controller;
{
	our %ViewInstCache;
	sub get_view
	{
		my $self = shift;
		my $view_code = shift;
		
		my $pkg = $AppCore::Config::THEME_MODULE;
		if(!$pkg )
		{
			$pkg = 'Content::Page::ThemeEngine';
		}
		
		$view_code = 'default' if !$view_code;
		
		if($pkg->can('new'))
		{
			return $ViewInstCache{$pkg} if $ViewInstCache{$pkg};
			
			$ViewInstCache{$pkg} = $pkg->new();
			
			return $ViewInstCache{$pkg}->get_view($view_code);
		}
		else
		{
			return $pkg->get_view($view_code);
		}
	}
	
	sub process_page
	{
		my $self = shift;
		my $type_dbobj = shift;
		my $req  = shift;
		my $r    = shift;
		my $page_obj = shift;
		
		# No view code will just return the BasicView derivitve which just uses the basic.tmpl template
		my $view_code = $type_dbobj->view_code;
		
		# Get a view module from the template based on view code so the template can choose to dispatch a view to a different object if needed
		my $view = $self->get_view($view_code);
		
		# Pass the view code onto the view output function so that it can aggregate different view types into one module
		$view->output($view_code,$req,$r,$page_obj);
	};

};

package Content::Page::ThemeEngine;
{
	sub new
	{
		bless {}, shift;
	}
	
	sub get_view
	{
		my $self = shift;
		my $code = shift;
		$self->{view_code} = $code;
		return $self;
	}

	sub output
	{
		my $self = shift;
		my $view_code = shift;
		my $req  = shift;
		my $r    = shift;
		my $page_obj = shift;
		my $parameters = shift || {};
		
		my $tmpl = AppCore::Web::Common::load_template("tmpl/basic.tmpl");
		$tmpl->param('page_'.$_ => $page_obj->get($_)) foreach $page_obj->columns;
		
		#$r->output($page_obj->content);
		$r->output($tmpl->output);
	};
};

1;
