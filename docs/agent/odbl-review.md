# ODbL 재배포 조건 점검 — 원문 인용 (agent용)

- 목적: 묵묵 데이터 팩(OSM 파생 데이터)을 앱 다운로드로 배포할 때 ODbL 조건을 확인하기 위한 근거 모음
- 작성: 2026-11-05. 원문은 web-fetch 에이전트가 가져왔다. 법률 해석은 포함하지 않는다.
- 법률 판단은 **법률 자문**이 맡는다(사람용 문서 `docs/human/odbl-review.md` 참고).

## 출처
- ODbL 1.0 원문: https://opendatacommons.org/licenses/odbl/1-0/
- OSM 저작권 안내: https://www.openstreetmap.org/copyright
- OSM 재단 출처 표기 가이드: https://osmfoundation.org/wiki/Licence/Attribution_Guidelines (wiki.osmfoundation.org에서 리디렉션)

**확인 한계:** 위 원문은 HTML 렌더링본에서 옮겼다. PDF·plain text와의 대조는 하지 않았다. 확인하지 못한 문서: "Produced Work - Guideline", "Substantial Guideline", OSMF Licence 페이지, ODbL 요약본.

---

## A. 파생 데이터베이스(Derivative Database) 정의
- 조항: Section 1.0
- 원문: "Derivative Database" – Means a database based upon the Database, and includes any translation, adaptation, arrangement, modification, or any other alteration of the Database or of a Substantial part of the Contents. This includes, but is not limited to, Extracting or Re-utilising the whole or a Substantial part of the Contents in a new Database.

## B. 제작물(Produced Work) 정의
- 조항: Section 1.0
- 원문: "Produced Work" – a work (such as an image, audiovisual material, text, or sounds) resulting from using the whole or a Substantial part of the Contents (via a search or other query) from this Database, a Derivative Database, or this Database as part of a Collective Database.

## C. 파생 데이터베이스를 공개적으로 사용할 때의 동일 조건 공개(Share-Alike)
- 조항: Section 4.4 a, 4.4 b, 4.4 c
- 4.4 a: "Any Derivative Database that You Publicly Use must be only under the terms of:" (i. "This License;" ii. "A later version of this License similar in spirit to this License; or" iii. "A compatible license.")
- 4.4 b: "For the avoidance of doubt, Extraction or Re-utilisation of the whole or a Substantial part of the Contents into a new database is a Derivative Database and must comply with Section 4.4."
- 4.4 c: "Derivative Databases and Produced Works. A Derivative Database is Publicly Used and so must comply with Section 4.4. if a Produced Work created from the Derivative Database is Publicly Used."
- "Publicly" 정의(Section 1.0): "“Publicly” – means to Persons other than You or under Your control by either more than 50% ownership or by the power to direct their activities (such as contracting with an independent consultant)."
- "Use" 정의(Section 1.0): "distributing, copying, publicly performing, publicly displaying, and preparing derivative works of the Database" 포함.

## D. 파생 데이터베이스 공개 시 요구 사항
- 조항: Section 4.6, 4.2 a, 4.2 b
- 4.6: "If You Publicly Use a Derivative Database or a Produced Work from a Derivative Database, You must also offer to recipients of the Derivative Database or Produced Work a copy in a machine readable form of:"
  - a. "The entire Derivative Database; or"
  - b. "A file containing all of the alterations made to the Database or the method of making the alterations to the Database (such as an algorithm), including any additional Contents, that make up all the differences between the Database and the Derivative Database."
- 4.6 후속: "The Derivative Database (under a.) or alteration file (under b.) must be available at no more than a reasonable production cost for physical distributions and free of charge if distributed over the internet."
- 4.2 a: "Do so only under the terms of this License or another license permitted under Section 4.4;"
- 4.2 b: "Include a copy of this License (or, as applicable, a license permitted under Section 4.4) or its Uniform Resource Identifier (URI) with the Database or Derivative Database, including both in the Database or Derivative Database and in any relevant documentation;"

## E. 제작물을 공개적으로 사용할 때의 출처 표기(Attribution)
- 조항: Section 4.3, 4.3 a
- 4.3: "Creating and Using a Produced Work does not require the notice in Section 4.2. However, if you Publicly Use a Produced Work, You must include a notice associated with the Produced Work reasonably calculated to make any Person that uses, views, accesses, interacts with, or is otherwise exposed to the Produced Work aware that Content was obtained from the Database, Derivative Database, or the Database as part of a Collective Database, and that it is available under this License."
- 4.3 a 예시 문구: "Contains information from DATABASE NAME, which is made available here under the Open Database License (ODbL)."
- 4.3 a 링크 요건: "DATABASE NAME should be replaced with the name of the Database and a hyperlink to the URI of the Database. “Open Database License” should contain a hyperlink to the URI of the text of this License. If hyperlinks are not possible, You should include the plain text of the required URI’s with the above notice."

## F. 내부 사용은 공개 사용이 아님
- 조항: Section 4.5 c (및 4.5 b)
- 4.5 c: "c. Use of a Derivative Database internally within an organisation is not to the public and therefore does not fall under the requirements of Section 4.4."
- 4.5 b: "Using this Database, a Derivative Database, or this Database as part of a Collective Database to create a Produced Work does not create a Derivative Database for purposes of Section 4.4;"
- OSM 가이드 원문: "Note that attribution is only necessary when a Produced Work is used Publicly (as defined by the ODbL). This guideline does not concern internal uses."

## G. OSM 재단 출처 표기 권장 문구와 링크
- OSM 가이드(Attribution Guidelines):
  - "Attribution must be to “OpenStreetMap”."
  - "Attribution must also make it clear that the data is available under the Open Database License. This may be done by making the text “OpenStreetMap” a link to openstreetmap.org/copyright, which has information about OpenStreetMap’s data sources (which OpenStreetMap needs to credit) as well as the ODbL."
  - "The historical forms of attribution “© OpenStreetMap contributors” or “© OpenStreetMap” are acceptable."
  - "OSM does not wish to claim credit for data or other material that did not come from it, so feel free to qualify the credit to explain what OSM content you are using. For example, if you have rendered OSM data to your own design, you may wish to use “Map data from OpenStreetMap.”"
  - Databases 항목: "You must include attribution to OpenStreetMap and either the text of the ODbL or a link to it as part of the database, derivative database, or database as part of a collective database."
  - Databases 항목: "You must include the notices in a location (such as a relevant directory) where users would be likely to look for it, such as a readme file, or within the data or metadata."
- 저작권 페이지(https://www.openstreetmap.org/copyright):
  - "Provide credit to OpenStreetMap by displaying our attribution notice."
  - "Make clear that the data is available under the Open Database License."
  - "Generally speaking, to make clear that the data is available under the Open Database License, you may link to [this copyright page](/copyright). If you are distributing OSM in data form, please name and link directly to the license(s)."
  - "In media where links are not possible (e.g. printed works), please include the full URL on the page, e.g. https://www.openstreetmap.org/copyright."
- 참고: 가이드는 "© OpenStreetMap contributors"를 권장 문구로 명시하지 않고 "historical forms"로 분류해 "acceptable"이라고만 한다.

## H. 벡터 타일(mbtiles, MVT)의 분류
- 확인한 3개 페이지 어디에도 "vector tile", "mbtiles", "MVT"에 대한 분류 문장이 없다. **직접 언급 없음.**
- 참고: copyright 페이지의 "we cannot provide a free-of-charge map API or map tiles for third-parties"는 OSMF 서비스 정책 문장이며 분류 기준이 아니다.

---

## 확인하지 못한 항목
- "Produced Work - Guideline" (Machine learning models 항목 참조)
- "Substantial Guideline" (정적 이미지 기준 언급)
- "Geocoding - Guideline"
- OSMF Licence 페이지 (https://osmfoundation.org/Licence)
- ODbL 1.0 요약본과 plain text 버전
- H항 (벡터 타일) 판단 근거 — 위 문서들에 있을 가능성이 있으나 확인하지 못함
