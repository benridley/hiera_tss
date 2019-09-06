

## hiera_tss : a Thycotic Secret Server data provider function (backend) for Hiera 5

### Description

This is a hiera backend that allows you to query Thycotic Secret Server over its rest API. It exposes the key 'secret_server::#{secret_id}' to your Hiera instance, and returns a hash wrapped in Puppet's sensitive type. 

### Compatibility

* Compatible with Hiera 5, that ships with Puppet 4.9+

### Requirements

Only dependencies are the net/http and json gems for Ruby which ship with Puppet.

### Configuration

The following is an example Hiera 5 hiera.yaml configuration for use with hiera_tss

```yaml
---
version: 5

hierarchy:
  - name: "Hiera TSS lookup"
    lookup_key: hiera_tss
    uri: https://secretserver.mydomain.com
    options:
      auth_file: '/etc/puppetlabs/secret_server.config'
      use_ssl: true
      ssl_verify: true
      ca_file: '/etc/pki/tls/ca_bundle.pem'
```

The following mandatory Hiera 5 options must be set for each level of the hierarchy.

`name`: A human readable name for the lookup
`lookup_key`: This option must be set to `hiera_tss`
`uri`: a single URI.

#### SSL options

`use_ssl:`: When set to true, enable SSL (default: false)

`ca_file`: Specify a CA cert for use with SSL

`ca_path`: Specify a CA path for use with SSL

`ssl_verify`: Specify whether to verify SSL certificates (default: true)

`auth_file` : The path of a file on your Puppet Master that contains authentication information for Secret Server. It should follow the format:

  ```
  username=secret_server_username
  password=secret_password
  domain=secret_domain (optional, for when you're doing AD integration)
  ```

### How to use the hiera_tss

Lookup a key using secret_server::#{secret_id}. If found, the returned value will be a hash that follows the format:
```
{
  "Username" : example_username
  "Password" : example_password
}
```
However, **the returned hash will be wrapped by Puppet's 'Sensitive' type** which is intended to prevent it showing up in logs. To use the values, you must unwrap the hash first. 

``` Puppet
  $my_username = $hiera_value.unwrap['Username']
  $my_password = $hiera_value.unwrap['Password']
```

For best results, use a yaml file or similar to store more meaningful key names, and then interpolate the values using the hiera_tss backend. An example would be:

```mydata.yaml
server_root_account:     "%{alias('secret_server::32')}"
```

If you're using your values in a file resource, it's a good idea to suppress the diff by setting `show_diff => false`, this will prevent the password from showing up in reports. 

To learn more about how Hiera interpolates values and the syntax required, check [The official Puppet documentation](https://puppet.com/docs/puppet/4.10/hiera_subkey.html)

Special Thanks to Craig Dunn and hiera-http for the foundations of this module.
