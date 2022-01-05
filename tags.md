---
layout: archive-taxonomies
permalink: /tags/
title: tags
type: tags
---

{% for lang in site.languages %}
  {% if forloop.index0 == 0 %}
    <a href="{{ site.copybaseurl }}{{ page.permalink }}" class="footer__link">{{ lang }}</a>
  {% else %}
    |<a href="{{ site.copybaseurl }}/{{ lang }}{{ page.permalink }}" class="footer__link">{{ lang }}</a>
  {% endif %}
{% endfor %}