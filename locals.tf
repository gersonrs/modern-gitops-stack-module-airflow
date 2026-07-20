locals {

  tag = "v1.8.0"

  domain      = format("airflow.%s", trimprefix("${var.subdomain}.${var.base_domain}", "."))
  domain_full = format("airflow.%s.%s", trimprefix("${var.subdomain}.${var.cluster_name}", "."), var.base_domain)

  mlflow = var.mlflow != null ? base64encode("http://${var.mlflow.endpoint}:5000/?__extra__=%7B%7D") : base64encode("http://localhost:5000")
  git_sync_ssh_key_volume = [
    {
      name = "config"
      configMap = {
        name        = "airflow-config"
        defaultMode = 420
      }
    },
    {
      name = "git-sync-ssh-key"
      secret = {
        secretName  = "airflow-ssh-secret"
        defaultMode = 288
      }
  }]
  git_sync_ssh_key_volume_mount = [
    {
      name              = "git-sync-ssh-key"
      mountPath         = "/etc/git-secret/ssh"
      readOnly          = true
      recursiveReadOnly = "Disabled"
    },
    {
      name              = "config"
      mountPath         = "/etc/git-secret/known_hosts"
      readOnly          = true
      recursiveReadOnly = "Disabled"
    }
  ]
  # 1. Definição do Volume Vazio
  plugins_volume = {
    name     = "plugins-volume"
    emptyDir = {}
  }

  # 2. Definição da Montagem no Container Principal
  plugins_volume_mount = {
    name      = "plugins-volume"
    mountPath = "/opt/airflow/plugins"
    subPath   = "repo/plugins"
  }

  # 3. Definição do InitContainer do Git-Sync
  git_sync_plugins_init = {
    name            = "git-sync-plugins"
    image           = "registry.k8s.io/git-sync/git-sync:v4.4.2"
    imagePullPolicy = "IfNotPresent"
    env = [
      { name = "GIT_SYNC_REV", value = "HEAD" },
      { name = "GITSYNC_REF", value = "HEAD" },
      { name = "GIT_SYNC_BRANCH", value = var.gitsync.branch },
      { name = "GIT_SYNC_REPO", value = var.gitsync.repo },
      { name = "GITSYNC_REPO", value = var.gitsync.repo },
      { name = "GIT_SYNC_DEPTH", value = "1" },
      { name = "GITSYNC_DEPTH", value = "1" },
      { name = "GIT_SYNC_ROOT", value = "/git" },
      { name = "GITSYNC_ROOT", value = "/git" },
      { name = "GIT_SYNC_DEST", value = "repo" },
      { name = "GITSYNC_LINK", value = "repo" },
      { name = "GIT_SYNC_ADD_USER", value = "true" },
      { name = "GITSYNC_ADD_USER", value = "true" },
      { name = "GIT_SYNC_ONE_TIME", value = "true" },
      { name = "GITSYNC_ONE_TIME", value = "true" },

      # SSH (Reaproveitando secrets do chart)
      { name = "GIT_SSH_KEY_FILE", value = "/etc/git-secret/ssh" },
      { name = "GITSYNC_SSH_KEY_FILE", value = "/etc/git-secret/ssh" },
      { name = "GIT_SYNC_SSH", value = "true" },
      { name = "GITSYNC_SSH", value = "true" },
      { name = "GIT_KNOWN_HOSTS", value = "true" },
      { name = "GITSYNC_SSH_KNOWN_HOSTS", value = "true" },
      { name = "GIT_SSH_KNOWN_HOSTS_FILE", value = "/etc/git-secret/known_hosts" },
      { name = "GITSYNC_SSH_KNOWN_HOSTS_FILE", value = "/etc/git-secret/known_hosts" }
    ]
    volumeMounts = [
      { name = "plugins-volume", mountPath = "/git" },
      { name = "git-sync-ssh-key", mountPath = "/etc/git-secret/ssh", readOnly = true, subPath = "gitSshKey" },
      { name = "config", mountPath = "/etc/git-secret/known_hosts", readOnly = true, subPath = "known_hosts" }
    ]
    securityContext = {
      runAsUser = 65533
    }
  }

  helm_values = [{
    airflow = {
      fernetKey = "${var.fernetKey}"
      images = {
        airflow = {
          repository = "gersonrs/airflow"
          tag        = local.tag
        }
      }
      volumes = [
        {
          name = "airflow-airflow-connections"
          configMap = {
            name = "airflow-airflow-connections"
          }
        }
      ]
      executor               = "CeleryExecutor,KubernetesExecutor"
      apiSecretKeySecretName = "airflow-api-secret-key"

      workers = {
        celery = {
          replicas = 2
          persistence = {
            enabled = false
            size    = "10Gi"
          }
          extraVolumes        = [local.plugins_volume]
          extraVolumeMounts   = [local.plugins_volume_mount]
          extraInitContainers = [local.git_sync_plugins_init]
        }
      }
      scheduler = {
        extraVolumes        = concat([local.plugins_volume], local.git_sync_ssh_key_volume)
        extraVolumeMounts   = concat([local.plugins_volume_mount], local.git_sync_ssh_key_volume_mount)
        extraInitContainers = [local.git_sync_plugins_init]
      }

      createUserJob = {
        useHelmHooks   = false
        applyCustomEnv = false
        jobAnnotations = {
          "argocd.argoproj.io/hook" : "Sync"
        }
      }
      migrateDatabaseJob = {
        useHelmHooks   = false
        applyCustomEnv = false
        jobAnnotations = {
          "argocd.argoproj.io/hook" : "Sync"
        }
      }
      # defaultUser = {
      #   enabled = false
      # }
      ingress = {
        enabled = false
      }
      pgbouncer = {
        enabled = true
      }
      data = {
        metadataSecretName = "airflow-metadata-secret"
      }
      postgresql = {
        enabled = false
      }
      triggerer = {
        persistence = {
          enabled = false
          size    = "10Gi"
        }
        extraVolumes        = [local.plugins_volume]
        extraVolumeMounts   = [local.plugins_volume_mount]
        extraInitContainers = [local.git_sync_plugins_init]
      }
      dagProcessor = {
        extraVolumes        = [local.plugins_volume]
        extraVolumeMounts   = [local.plugins_volume_mount]
        extraInitContainers = [local.git_sync_plugins_init]
      }
      logs = {
        persistence = {
          enabled          = false
          size             = "10Gi"
          storageClassName = "standard"
        }
      }
      dags = {
        gitSync = {
          enabled      = true
          repo         = var.gitsync.repo
          branch       = var.gitsync.branch
          rev          = "HEAD"
          depth        = 2
          maxFailures  = 2
          subPath      = "dags"
          sshKeySecret = "airflow-ssh-secret"
          knownHosts   = "|-\n|1|yutcXh9HhbK6KCouq3xMQ38B9ns=|V9zQ39gzVxSZ75WU78CGJiVKCOk= ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=\n|1|7ww9iNXn8d1jtXlaDjt+fYpsRi0=|vfHsTzw+QATWkCKD7kgG2jhu/1w= ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg="
        }
      }
      env = [
        {
          name  = "AIRFLOW_CONN_POSTGRES_TESTE"
          value = "${base64encode("postgresql://${var.database.user}:${var.database.password}@${var.database.endpoint}:5432/teste")}"
        },
        {
          name  = "MLFLOW_TRACKING_URI"
          value = var.mlflow != null ? "http://${var.mlflow.endpoint}:5000" : "http://localhost:5000"
        },
        {
          name  = "MLFLOW_S3_ENDPOINT_URL"
          value = "http://${var.storage.endpoint}"
        },
        {
          name  = "AWS_ENDPOINT"
          value = "http://${var.storage.endpoint}"
        },
        {
          name  = "AWS_ACCESS_KEY_ID"
          value = "${var.storage.access_key}"
        },
        {
          name  = "AWS_SECRET_ACCESS_KEY"
          value = "${var.storage.secret_access_key}"
        },
        {
          name  = "AWS_REGION"
          value = "eu-west-1"
        },
        {
          name  = "AWS_ALLOW_HTTP"
          value = "true"
        },
        {
          name  = "AWS_S3_ALLOW_UNSAFE_RENAME"
          value = "true"
        },
        {
          name  = "GIT_PYTHON_REFRESH"
          value = "quiet"
        },
      ]
      extraSecrets = {
        airflow-metadata-secret = {
          data = "connection: ${base64encode("postgresql://${var.database.user}:${var.database.password}@${var.database.endpoint}:5432/${var.database.database}")}"
        }
        airflow-api-secret-key = {
          data = "api-secret-key: ${base64encode(resource.random_password.airflow_api_secret_key.result)}"
        }
      }
      extraEnv = <<-EOT
        - name: AIRFLOW__LOGGING__REMOTE_LOGGING
          value: "True"
        - name: AIRFLOW__LOGGING__REMOTE_BASE_LOG_FOLDER
          value: "s3://airflow/logs"
        - name: AIRFLOW__LOGGING__REMOTE_LOG_CONN_ID
          value: "conn_minio_s3"
        - name: AIRFLOW__KUBERNETES_EXECUTOR__DELETE_WORKER_PODS
          value: "True"
        - name: AIRFLOW__KUBERNETES_EXECUTOR__DELETE_WORKER_PODS_ON_FAILURE
          value: "True"
        - name: AIRFLOW__CORE__ALLOWED_DESERIALIZATION_CLASSES
          value: airflow\.* astro\.*
        - name: AIRFLOW__CORE__XCOM_BACKEND
          value: "airflow.providers.common.io.xcom.backend.XComObjectStorageBackend"
        - name: AIRFLOW__COMMON_IO__XCOM_OBJECTSTORAGE_PATH
          value: "s3://conn_minio_s3@airflow/xcom"
        - name: AIRFLOW__WORKERS__STATE_STORE_BACKEND
          value: "airflow.providers.common.io.state_store.backend.StateStoreObjectStorageBackend"
        - name: AIRFLOW__COMMON_IO__STATE_STORE_OBJECTSTORAGE_PATH
          value: "s3://conn_minio_s3@airflow/state"
      EOT
      extraConfigMaps = {
        airflow-airflow-connections = {
          data = <<-EOT
            script.sh: |
              #!/usr/bin/env bash
              conn=$(airflow connections list)
              if [ "$conn" = "No data found" ]; then
                connections=$(env | grep "^conn_" | sort)
                echo $connections | tr " " "\n" > conn.env
                cat conn.env
                airflow connections import conn.env
              else
                airflow connections list
              fi
          EOT
        }
      }
      apiServer = {
        env = [
          {
            name  = "OAUTH2_METADATA_URL"
            value = "${var.oidc.issuer_url}/.well-known/openid-configuration"
          },
          {
            name  = "OAUTH2_SERVER_METADATA_URL"
            value = "${var.oidc.issuer_url}/.well-known/openid-configuration"
          }
        ]
        apiServerConfig   = <<-EOT
            from airflow.providers.fab.auth_manager.security_manager.override import FabAirflowSecurityManagerOverride
            from flask_appbuilder.security.manager import AUTH_OAUTH
            import logging
            import os
            from typing import Union, Any

            log = logging.getLogger(__name__)
            log.setLevel(os.getenv("AIRFLOW__LOGGING__FAB_LOGGING_LEVEL", "INFO"))

            CSRF_ENABLED = True
            AUTH_TYPE = AUTH_OAUTH

            AUTH_ROLE_ADMIN = 'Admin'
            AUTH_ROLE_PUBLIC = 'Public'
            AUTH_ROLE_VIEWER = 'Viewer'
            AUTH_ROLE_USER = 'User'

            AUTH_USER_REGISTRATION = True
            AUTH_USER_REGISTRATION_ROLE = AUTH_ROLE_VIEWER

            AUTH_ROLES_SYNC_AT_LOGIN = True

            AUTH_ROLES_MAPPING = {
                "Viewer": ["Viewer"],
                "Admin": ["Admin"],
                "User": ["User"],
                "Op": ["Op"],
            }

            OAUTH_PROVIDERS = [{
                "name": "keycloak",
                "token_key":"access_token",
                "icon":"fa-address-card",
                "remote_app": {
                    "api_base_url": "${var.oidc.issuer_url}/protocol/",
                    "access_token_url": "${var.oidc.token_url}",
                    "authorize_url": "${var.oidc.oauth_url}",
                    "userinfo_url": "${var.oidc.api_url}",
                    "server_metadata_url": "${var.oidc.issuer_url}/.well-known/openid-configuration",
                    "request_token_url": None,
                    "client_id": "${var.oidc.client_id}",
                    "client_secret": "${var.oidc.client_secret}",
                    "client_kwargs":{
                        "scope": "email profile openid",
                        "verify": False
                    },
                }
            }]
            def map_roles(team_list):
                team_role_map = {
                    "modern-gitops-stack-admins": AUTH_ROLE_ADMIN,
                    "modern-gitops-stack-editors": "Op",
                    "modern-gitops-stack-data-engineers": "Op",
                    "modern-gitops-stack-ml-engineers": "User",
                    "modern-gitops-stack-data-scientists": "User",
                    "modern-gitops-stack-viewers": AUTH_ROLE_VIEWER,
                }
                return list(set(team_role_map[team] for team in team_list if team in team_role_map))
            class CustomSecurityManager(FabAirflowSecurityManagerOverride):
                def get_oauth_user_info(self, provider, resp=None):
                    me = self.oauth_remotes[provider].get("openid-connect/userinfo")
                    me.raise_for_status()
                    data = me.json()
                    log.debug("User info from Keycloak: %s", data)
                    log.info("User info from Keycloak: %s", data)

                    groups = map_roles(data.get("groups", []))

                    if groups is None or len(groups) < 1:
                        groups = [AUTH_ROLE_PUBLIC]

                    log.info("User groups info: %s", groups)
                    return {
                        "username": data.get("preferred_username", ""),
                        "first_name": data.get("given_name", ""),
                        "last_name": data.get("family_name", ""),
                        "email": data.get("email", ""),
                        "role_keys": groups
                    }


            # Make sure to replace this with your own implementation of AirflowSecurityManager class
            SECURITY_MANAGER_CLASS = CustomSecurityManager
        EOT
        extraVolumes      = concat([local.plugins_volume], local.git_sync_ssh_key_volume)
        extraVolumeMounts = concat([local.plugins_volume_mount], local.git_sync_ssh_key_volume_mount)
        extraInitContainers = [
          local.git_sync_plugins_init,
          {
            image           = "gersonrs/airflow:${local.tag}"
            imagePullPolicy = "IfNotPresent"
            env = [
              {
                name  = "conn_kubernetes"
                value = "${base64encode("kubernetes:///?__extra__=%7B%22in_cluster%22%3A+true%2C+%22disable_verify_ssl%22%3A+false%2C+%22disable_tcp_keepalive%22%3A+false%7D")}"
              },
              {
                name  = "conn_minio_s3"
                value = "${base64encode("aws:///?region_name=eu-west-1&aws_access_key_id=${var.storage.access_key}&aws_secret_access_key=${var.storage.secret_access_key}&endpoint_url=http://${var.storage.endpoint}")}"
              },
              {
                name  = "conn_postegres_curated"
                value = "${base64encode("postgresql://${var.database.user}:${var.database.password}@${var.database.endpoint}:5432/curated")}"
              },
              {
                name  = "conn_postegres_data"
                value = "${base64encode("postgresql://${var.database.user}:${var.database.password}@${var.database.endpoint}:5432/data")}"
              },
              {
                name  = "conn_postegres_feature_store"
                value = "${base64encode("postgresql://${var.database.user}:${var.database.password}@${var.database.endpoint}:5432/feature_store")}"
              },
              {
                name  = "conn_mlflow"
                value = "${local.mlflow}"
              },
              {
                name = "AIRFLOW__DATABASE__SQL_ALCHEMY_CONN"
                valueFrom = {
                  secretKeyRef = {
                    name = "airflow-metadata-secret"
                    key  = "connection"
                  }
                }
              },
              {
                name = "AIRFLOW_CONN_AIRFLOW_DB"
                valueFrom = {
                  secretKeyRef = {
                    name = "airflow-metadata-secret"
                    key  = "connection"
                  }
                }
              },
              {
                name = "AIRFLOW__API__SECRET_KEY"
                valueFrom = {
                  secretKeyRef = {
                    name = "airflow-api-secret-key"
                    key  = "api-secret-key"
                  }
                }
              },
              {
                name = "AIRFLOW__CORE__FERNET_KEY"
                valueFrom = {
                  secretKeyRef = {
                    name = "airflow-fernet-key"
                    key  = "fernet-key"
                  }
                }
              },
            ]
            name = "config-connections"
            args = ["bash", "/opt/airflow/script.sh"]
            volumeMounts = [
              {
                name = "airflow-airflow-connections"
                mountPath : "/opt/airflow/script.sh"
                subPath : "script.sh"
                readOnly : true
              }
            ]
          }
        ]
      }
    }
  }]

  helm_values_httproute = [{
    httproute = {
      enabled           = true
      host              = local.domain
      gateway_name      = var.gateway_name
      gateway_namespace = var.gateway_namespace
      backend_service   = "airflow-api-server"
      backend_port      = 8080
    }
  }]
}
