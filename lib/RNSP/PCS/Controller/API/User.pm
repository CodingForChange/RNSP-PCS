
package RNSP::PCS::Controller::API::User;

use Moose;

use JSON qw(encode_json);

BEGIN { extends 'Catalyst::Controller::REST' }

__PACKAGE__->config( default => 'application/json' );

sub base : Chained('/api/base') : PathPart('user') : CaptureArgs(0) {
  my ( $self, $c ) = @_;
  $c->stash->{collection} = $c->model('DB::User');

}

sub object : Chained('base') : PathPart('') : CaptureArgs(1) {
  my ( $self, $c, $id ) = @_;

  $self->status_forbidden( $c, message => "access denied", ), $c->detach
    unless $c->user->id == $id || $c->check_any_user_role(qw(admin));

  $c->stash->{object} = $c->stash->{collection}->search_rs( { id => $id } );
  $c->stash->{object}->count > 0 or $c->detach('/error_404');


}

sub user_file : Chained('object') : PathPart('arquivo') : Args(1) : ActionClass('REST') {
}

use JSON;
use Path::Class qw(dir);
sub user_file_POST {
    my ( $self, $c, $classe ) = @_;

    my $t = new Text2URI();

    $classe = $t->translate(substr($classe, 0, 15));
    $classe ||= 'perfil';

    $c->res->content_type('application/json; charset=utf8');

    my $upload = $c->req->upload('arquivo');
    if ($upload){
        my $user_id = $c->stash->{object}->next->id;
        my $filename = sprintf('user_%i_%s_%s',
            $user_id,
            $classe,
            substr($t->translate($upload->basename), 0, 200)
        );

        my $private_path = $c->config->{private_path} =~ /^\//o ?
                    dir($c->config->{private_path})->resolve . '/' . $filename :
            RNSP::PCS->path_to( $c->config->{private_path} , $filename );

        unless ($upload->copy_to( $private_path )){
            $c->res->body(to_json({ error => "Copy failed: $!" }));
            $c->detach;
        }
        chmod 0644, $private_path;

        my $public_url = $c->uri_for( $c->config->{public_url} . '/' . $filename )->as_string;

        # nao trocar por $c->user->obj por causa dos testes
        my $file = $c->model('DB::User')->find($user_id)->add_to_user_files({
            class_name   => $classe,
            public_url   => $public_url,
            private_path => $private_path
        });

        $c->res->body(to_json({ class_name => $classe, id => $file->id, location => $public_url }));

    }else{
        $c->res->body(to_json({ error => 'no upload found' }));
    }

    $c->detach;
}



sub user : Chained('object') : PathPart('') : Args(0) : ActionClass('REST') {
  my ( $self, $c ) = @_;

}

=pod

=encoding utf-8

detalhe do usuario

GET /api/user/$id

Retorna:

    {
        roles => [foo],
        city => {..},
        name => 'x',
        email => 'y'
    }

=cut

sub user_GET {
    my ( $self, $c ) = @_;


    my $user  = $c->stash->{object}->next;
    my %attrs = $user->get_inflated_columns;
    $self->status_ok(
        $c,
        entity => {
        roles => [ map { $_->name } $user->roles ],
        files => {
            map { $_->class_name => $_->public_url } $user->user_files->search(undef, {
                order_by => 'created_at'
        }) },

        nome_responsavel_cadastro => $user->nome_responsavel_cadastro,
        estado => $user->estado,
        telefone => $user->telefone,
        email_contato => $user->email_contato,
        telefone_contato => $user->telefone_contato,
        cidade => $user->cidade,
        bairro => $user->bairro,
        cep => $user->cep,
        endereco => $user->endereco,

        $user->city
        ? (
            city => $c->uri_for(
            $c->controller('API::City')->action_for('city'),
            [ $attrs{city_id} ] )->as_string
            )
        : (),
        map { $_ => $attrs{$_}, } qw(name email)
        }
    );
}

=pod

atualizar usuario

POST /api/user/$id

Param:

    user.update.name                Texto, Requerido: Nome completo do usuário
    user.update.email               Texto, Requerido: Email válido
    user.update.password            Texto, Requerido: Senha maior que 6 caracteres contendo letras, números e símbolos
    user.update.confirm_password    Texto, Requerido: Mesma senha anterior, para confirmação
    user.update.role                Texto, Não Requerido: qual o role dele (admin,user,app)

    user.update.city_id             Int, Requerido: qual a cidade ele pertence
    user.update.prefeito            0 ou 1, Nao Requerido: eh prefeito?
    user.update.movimento           0 ou 1, Nao Requerido: eh movimento?

    nome_responsavel_cadastro, estado, telefone, email_contato, telefone_contato, cidade, bairro, cep, endereco,
Retorna:

    { name => '', id => '' }

=cut

sub user_POST {
  my ( $self, $c ) = @_;
  $c->req->params->{user}{update}{id} = $c->stash->{object}->next->id;

  my $dm = $c->model('DataManager');

  $self->status_bad_request( $c, message => encode_json( $dm->errors ) ), $c->detach
    unless $dm->success;

  my $user = $dm->get_outcome_for('user.update');

  $self->status_accepted(
    $c,
    location =>
      $c->uri_for( $self->action_for('user'), [ $user->id ] )->as_string,
    entity => { name => $user->name, id => $user->id }
    ),
    $c->detach
    if $user;
}


=pod

apagar usuario

DELETE /api/user/$id

Retorna: No-content ou Gone

=cut

sub user_DELETE {
  my ( $self, $c ) = @_;

  my $user = $c->stash->{object}->next;
  $self->status_gone( $c, message => 'deleted' ), $c->detach unless $user;

  $user->user_roles->delete;
  $user->sessions->delete;
  $user->delete;

  $self->status_no_content($c);
}

sub list : Chained('base') : PathPart('') : Args(0) : ActionClass('REST') {
}


=pod

listar usuarios

GET /api/user

Retorna:

    {   users => [
            { name => 'JOHANSSON', email => 'ae@bor.ai', id => -1, city => { name => 'SP', id => 1}},
            ...
        ]
    }
=cut

sub list_GET {
  my ( $self, $c ) = @_;

  $self->status_forbidden( $c, message => "access denied", ), $c->detach
    unless $c->check_any_user_role(qw(admin));


  $self->status_ok(
    $c,
    entity => {
      users => [
        map {
          +{
            name => $_->{name},
            email => $_->{email},

            nome_responsavel_cadastro => $_->{nome_responsavel_cadastro},
            estado => $_->{estado},
            telefone => $_->{telefone},
            email_contato => $_->{email_contato},
            telefone_contato => $_->{telefone_contato},
            cidade => $_->{cidade},
            bairro => $_->{bairro},
            cep => $_->{cep},
            endereco => $_->{endereco},

            $_->{city}
            ? (
              city => {
                name => $_->{city}->{name},
                id   => $_->{city}->{id}
              }
              )
            : (),
            url => $c->uri_for_action( $self->action_for('user'), [ $_->{id} ] )
              ->as_string
            }
          } $c->stash->{collection}
          ->search_rs( undef, { prefetch => 'city' } )->as_hashref->all
      ]
    }
  );
}


=pod

criar usuario

POST /api/user

Param:

    user.create.name                Texto, Requerido: Nome completo do usuário
    user.create.email               Texto, Requerido: Email válido
    user.create.password            Texto, Requerido: Senha maior que 6 caracteres contendo letras, números e símbolos
    user.create.confirm_password    Texto, Requerido: Mesma senha anterior, para confirmação
    user.create.role                Texto, Não Requerido: qual o role dele (admin,user,app)

    user.create.city_id             Int, Nao Requerido: qual a cidade ele pertence
    user.create.prefeito            0 ou 1, Nao Requerido: eh prefeito?
    user.create.movimento           0 ou 1, Nao Requerido: eh movimento?

    * Persona 1: admin
    * Persona 2: user
    * Persona 3: app

Retorna:

    { name => 'JOHANSSON', id => -1, city => { name => 'SP', id => 1}}

=cut

sub list_POST {
  my ( $self, $c ) = @_;


  my $dm = $c->model('DataManager');

  $self->status_bad_request( $c, message => encode_json( $dm->errors ) ), $c->detach
    unless $dm->success;

  $c->req->params->{user}{create}{role} ||= 'user';

  my $user = $dm->get_outcome_for('user.create');
  $self->status_created(
    $c,
    location => $c->uri_for( $self->action_for('user'), [ $user->id ] )->as_string,
    entity => {
      name => $user->name,
      id   => $user->id,
      $user->city
      ? ( city =>
          { name => $user->city->name, id => $user->city->id } )
      : (),
    }
  );

}



with 'RNSP::PCS::TraitFor::Controller::Search';
1;

