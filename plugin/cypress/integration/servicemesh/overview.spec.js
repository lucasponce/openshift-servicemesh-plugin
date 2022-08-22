/// <reference types="cypress" />

describe('servicemesh -> overview', () => {
   beforeEach(() => {
      cy.openServiceMeshOverview();
   });

   it('displays the Kiali Overview page', () => {
      // Left navigation menu link exists
      cy.get('a[href$="/servicemeshoverview"]').should('be.visible');

      // Wait until OpenShift Console loads its page content (i.e. plugins)
      cy.get('div[data-test="loading-indicator"]').should('not.exist');

      // Locate the iframe and search elements inside
      // From https://www.cypress.io/blog/2020/02/12/working-with-iframes-in-cypress/
      cy.get('iframe[data-test="overview"]')
          .its('0.contentWindow.document.body').should('not.be.undefined')
          .then(cy.wrap)
          .find('#refresh_button');
   });
});