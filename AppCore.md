# Introduction #

This article will example the various classes available in the 'AppCore::' namespace.


# Details #

Alphabetically, the following modules are available:
  * AppCore::AuthUtil - _Utility routines for user HTTP authentication, no UI_
  * AppCore::Common - _Common non-web-specific routines, such as date handling_
  * AppCore::Web::Common - _Common web-specific routines, such as entities, escaping, redirecting, etc_
  * AppCore::Web::Module - _Base-class for 'modules' in AppCore, provides enumeration routines_
  * AppCore::Web::Result - _Basic result encapsulation for an HTTP request_
  * AppCore::Web::Request - _Basic request encapsulation for an HTTP request_
  * AppCore::RunContext - _Collection of variables global to the current request, accessed via AppCore::Common->context()_
  * AppCore::Config - _Symlinked to appcore/conf/appcore.conf, provides configuration variables_
  * AppCore::User - _AppCore::DBI-subclass representing a single user in the datbase_
  * AppCore::DBI - _Extends Class::DBI to provide a robust meta-data system for reflection and automatic schema updating/creation_
