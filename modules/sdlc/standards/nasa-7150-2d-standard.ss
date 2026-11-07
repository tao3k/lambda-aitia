;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; -*- Gerbil -*-
;;; Lightweight NASA standard owner for module configuration and scenarios.
;;; Applicability, review, and certification algorithms live in their own
;;; standard modules and do not enter the Profile import closure.

(import (only-in :clan/poo/object .get .o .ref)
        (only-in "sources.ss"
                 Nasa7150_2DSourcesLock))
(export make-nasa-7150-2d-standard)

(def chapter3-url
  "https://nodis3.gsfc.nasa.gov/displayDir.cfm?Internal_ID=N_PR_7150_002D_&page_name=Chapter3")

(def (make-nasa-7150-2d-standard standard-prototype catalog)
  (.o (:: @ standard-prototype) identity: "nasa/sdlc/npr-7150.2" edition: "D"
      source-lock-digest: (.ref Nasa7150_2DSourcesLock 'digest)
      source-url: chapter3-url verified-on: "2026-09-12"
      effective-date: "2022-03-08" expiration-date: "2027-03-08"
      applicability-source:
      "https://nodis3.gsfc.nasa.gov/displayDir.cfm?Internal_ID=N_PR_7150_002D_&page_name=AppendixC"
      tailoring-source:
      "https://nodis3.gsfc.nasa.gov/displayDir.cfm?Internal_ID=N_PR_7150_002D_&page_name=Chapter2"
      requirements: (.get catalog requirements)
      catalog-coverage: 'chapters2-through5-and-appendix-c-complete
      source-digests: (.get catalog source-digests)
      executable-coverage: 'source-review-and-conditional-applicability
      traceability-table-status: 'class-conditional-source-checks))
