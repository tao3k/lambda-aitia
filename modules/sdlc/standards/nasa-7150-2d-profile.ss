;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;;
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; -*- Gerbil -*-
;;; Lightweight NASA standard owner for module configuration and scenarios.
;;; Applicability, review, and certification algorithms live in their own
;;; standard modules and do not enter the Profile import closure.

(import (only-in :clan/poo/object .o .ref)
        :poo-flow/lambda-aitia/modules/sdlc/objects
        :poo-flow/lambda-aitia/modules/sdlc/standards/nasa-7150-2d-catalog
        (only-in :poo-flow/lambda-aitia/modules/sdlc/standards/sources
                 Nasa7150_2DSourcesLock))
(export Nasa7150_2D)

(def chapter3-url
  "https://nodis3.gsfc.nasa.gov/displayDir.cfm?Internal_ID=N_PR_7150_002D_&page_name=Chapter3")

(def Nasa7150_2D
  (.o (:: @ StandardProfile.) identity: "nasa/sdlc/npr-7150.2" edition: "D"
      source-lock-digest: (.ref Nasa7150_2DSourcesLock 'digest)
      source-url: chapter3-url verified-on: "2026-09-12"
      effective-date: "2022-03-08" expiration-date: "2027-03-08"
      applicability-source:
      "https://nodis3.gsfc.nasa.gov/displayDir.cfm?Internal_ID=N_PR_7150_002D_&page_name=AppendixC"
      tailoring-source:
      "https://nodis3.gsfc.nasa.gov/displayDir.cfm?Internal_ID=N_PR_7150_002D_&page_name=Chapter2"
      requirements: nasa-requirement-catalog
      catalog-coverage: 'chapters2-through5-and-appendix-c-complete
      source-digests: nasa-catalog-source-digests
      executable-coverage: 'source-review-and-conditional-applicability
      traceability-table-status: 'class-conditional-source-checks))
