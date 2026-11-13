{ pkgs }:

name:

let
  certificate = ./test-identities + "/${name}.pem";
  files =
    pkgs.runCommand "buildbarn-test-identity-${name}" { nativeBuildInputs = [ pkgs.openssl ]; }
      ''
        mkdir $out
        seed=$(printf %s ${name} | sha256sum | cut -c1-64)
        printf "$(printf %s "302e020100300506032b657004220420$seed" | sed 's/../\\x&/g')" \
          | openssl pkey -inform DER -out $out/key.pem
        openssl req -x509 -key $out/key.pem -subj /CN=${name} \
          -addext subjectAltName=DNS:${name} -addext extendedKeyUsage=serverAuth,clientAuth \
          -set_serial 1 -not_before 20260101000000Z -not_after 21260101000000Z -out $out/cert.pem
        cmp $out/cert.pem ${certificate}
      '';
in
{
  certificate = builtins.readFile certificate;
  install.systemd.services.buildbarn-test-identity = {
    description = "Give the test host the key its listed certificate belongs to, before the identity unit would make another";
    before = [ "buildbarn-identity.service" ];
    requiredBy = [ "buildbarn-identity.service" ];
    unitConfig.ConditionPathExists = "!/var/lib/buildbarn/identity/key.pem";
    serviceConfig.Type = "oneshot";
    script = ''
      install -D -m 0644 ${files}/key.pem /var/lib/buildbarn/identity/key.pem
      install -m 0644 ${files}/cert.pem /var/lib/buildbarn/identity/cert.pem
    '';
  };
}
