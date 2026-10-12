# syntax=docker/dockerfile:1
# =============================================================================
# Arcway : image de production
# -----------------------------------------------------------------------------
# Construction multi-stage
#   1. build   : JDK 17, compile et empaquète le jar, puis l'éclate en couches
#                pour un cache de couches efficace.
#   2. runtime : JRE 17 minimal, utilisateur non-root, aucun outil de build.
#
# Garanties
#   - Utilisateur non-root (UID/GID 10001, numérique : compatible avec les
#     politiques « runAsNonRoot »).
#   - Aucun secret dans l'image : tout arrive à l'exécution.
#     Le contexte de build exclut .env.
#   - Les tests ne sont PAS exécutés ici : ils le sont en CI avant
#     la construction de l'image.
#   - Le seul chemin inscriptible attendu à l'exécution est /tmp ; le conteneur
#     peut donc tourner en système de fichiers racine en lecture seule.
#
# Construction
#   docker build -t arcway:local \
#     --build-arg VERSION=0.0.1 \
#     --build-arg VCS_REF=$(git rev-parse HEAD) \
#     --build-arg BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ) .
#
# Mises à jour : les images de base sont suivies par Dependabot ;
# épingler par condensat (@sha256:...) pour des builds
# reproductibles lorsque le registre de déploiement le permet.
# =============================================================================

ARG JAVA_VERSION=17

# -----------------------------------------------------------------------------
# Étape 1 : build
# -----------------------------------------------------------------------------
FROM eclipse-temurin:${JAVA_VERSION}-jdk-alpine AS build

WORKDIR /build

# Wrapper Maven d'abord : couche stable, rarement invalidée.
COPY mvnw ./
COPY .mvn/ .mvn/
RUN chmod +x mvnw

# Descripteur de build, puis sources.
COPY pom.xml ./
COPY src/ src/

# Le cache Maven est conservé entre les builds : les dépendances ne
# sont pas retéléchargées à chaque modification du code.
# -DskipTests ignore Surefire ET Failsafe.
RUN --mount=type=cache,target=/root/.m2 \
    ./mvnw -B -ntp -DskipTests clean package \
    && cp target/*.jar application.jar

# Éclatement du jar en couches : les dépendances sont séparées du code
# de l'application, ce qui réduit le volume poussé à chaque release.
RUN java -Djarmode=tools -jar application.jar extract --layers --destination extracted

# -----------------------------------------------------------------------------
# Étape 2 : runtime
# -----------------------------------------------------------------------------
FROM eclipse-temurin:${JAVA_VERSION}-jre-alpine AS runtime

# Métadonnées OCI : renseignées par le pipeline de release.
ARG VERSION=0.0.0
ARG VCS_REF=unknown
ARG BUILD_DATE=unknown
LABEL org.opencontainers.image.title="arcway" \
      org.opencontainers.image.description="Arcway : plateforme multi-tenant de statistiques de basketball" \
      org.opencontainers.image.source="https://github.com/Darrylwin/Arcway" \
      org.opencontainers.image.licenses="AGPL-3.0-only" \
      org.opencontainers.image.vendor="DARCODE" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.created="${BUILD_DATE}"

# Correctifs de sécurité du système de base, puis utilisateur dédié sans shell
# de connexion ni répertoire personnel.
RUN apk upgrade --no-cache \
    && addgroup -S -g 10001 arcway \
    && adduser -S -u 10001 -G arcway -H -h /application -s /sbin/nologin arcway

WORKDIR /application

# Couches copiées de la plus stable à la plus changeante.
COPY --from=build /build/extracted/dependencies/ ./
COPY --from=build /build/extracted/spring-boot-loader/ ./
COPY --from=build /build/extracted/snapshot-dependencies/ ./
COPY --from=build /build/extracted/application/ ./

# Options JVM, surchargeables à l'exécution.
#   MaxRAMPercentage=75     : laisse de la marge hors tas.
#   ExitOnOutOfMemoryError  : un OOM tue le processus ; l'orchestrateur redémarre
#                             un conteneur sain plutôt qu'un processus dégradé.
ENV JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75 -XX:+ExitOnOutOfMemoryError -Dfile.encoding=UTF-8"

USER 10001:10001

# API. Le port d'Actuator est distinct en production et n'est volontairement pas publié.
EXPOSE 8080

# Sonde de READINESS
HEALTHCHECK --interval=30s --timeout=3s --start-period=60s --retries=3 \
    CMD ["sh", "-c", "wget -q --spider \"http://127.0.0.1:${ARCWAY_MANAGEMENT_PORT:-8080}/actuator/health/readiness\" || exit 1"]

# Forme exec : java est le processus 1 et reçoit directement SIGTERM, ce qui
# déclenche l'arrêt gracieux.
ENTRYPOINT ["java", "-jar", "application.jar"]
