package com.darcode.arcway.testsupport;

import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.ActiveProfiles;

/**
 * Socle commun des tests d'intégration : démarre l'application
 * complète sur un PostgreSQL réel.
 *
 * <p>{@code @ActiveProfiles("test")} charge application-test.yaml : sans lui,
 * les placeholders de application.yaml ne seraient pas résolus.
 *
 * <p>Spring met le contexte en cache : tous les tests qui partagent la même
 * configuration réutilisent le même contexte, ce qui garde la suite rapide.
 */
@SpringBootTest
@ActiveProfiles("test")
@Import(PostgresContainerConfig.class)
public abstract class AbstractIntegrationTest {
}
