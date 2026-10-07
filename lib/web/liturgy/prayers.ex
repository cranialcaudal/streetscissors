defmodule Web.Liturgy.Prayers do
  @moduledoc """
  The fixed prayers, in their traditional English wording.

  Every text here is the long-standing form of the old catechisms and prayer
  books, which is in the public domain, with one change made throughout:
  "Holy Spirit" for "Holy Ghost". The current liturgical translations of the
  same prayers are under copyright and are not used.
  """

  @prayers %{
    sign_of_the_cross:
      {"The Sign of the Cross",
       "In the name of the Father, and of the Son, and of the Holy Spirit. Amen."},
    apostles_creed:
      {"The Apostles' Creed",
       "I believe in God, the Father Almighty, Creator of heaven and earth; and in Jesus Christ, His only Son, our Lord; who was conceived by the Holy Spirit, born of the Virgin Mary, suffered under Pontius Pilate, was crucified, died, and was buried. He descended into hell; the third day He rose again from the dead; He ascended into heaven, and sitteth at the right hand of God, the Father Almighty; from thence He shall come to judge the living and the dead. I believe in the Holy Spirit, the holy Catholic Church, the communion of saints, the forgiveness of sins, the resurrection of the body, and life everlasting. Amen."},
    our_father:
      {"The Our Father",
       "Our Father, who art in heaven, hallowed be thy name; thy kingdom come; thy will be done on earth as it is in heaven. Give us this day our daily bread; and forgive us our trespasses as we forgive those who trespass against us; and lead us not into temptation, but deliver us from evil. Amen."},
    hail_mary:
      {"The Hail Mary",
       "Hail Mary, full of grace, the Lord is with thee; blessed art thou among women, and blessed is the fruit of thy womb, Jesus. Holy Mary, Mother of God, pray for us sinners, now and at the hour of our death. Amen."},
    glory_be:
      {"The Glory Be",
       "Glory be to the Father, and to the Son, and to the Holy Spirit. As it was in the beginning, is now, and ever shall be, world without end. Amen."},
    fatima:
      {"The Fatima Prayer",
       "O my Jesus, forgive us our sins, save us from the fires of hell, lead all souls to heaven, especially those in most need of thy mercy."},
    salve_regina:
      {"Hail, Holy Queen",
       "Hail, holy Queen, Mother of mercy, our life, our sweetness and our hope. To thee do we cry, poor banished children of Eve; to thee do we send up our sighs, mourning and weeping in this valley of tears. Turn then, most gracious Advocate, thine eyes of mercy toward us, and after this our exile, show unto us the blessed fruit of thy womb, Jesus. O clement, O loving, O sweet Virgin Mary. Pray for us, O holy Mother of God, that we may be made worthy of the promises of Christ. Amen."},
    regina_caeli:
      {"Queen of Heaven",
       "Queen of Heaven, rejoice, alleluia. For He whom thou didst merit to bear, alleluia, has risen as He said, alleluia. Pray for us to God, alleluia. Rejoice and be glad, O Virgin Mary, alleluia. For the Lord has truly risen, alleluia."},
    direct_our_actions:
      {"Prayer",
       "Direct, we beseech thee, O Lord, our actions by thy holy inspirations, and carry them on by thy gracious assistance, that every prayer and work of ours may begin always from thee, and by thee be happily ended. Through Christ our Lord. Amen."},
    pour_forth:
      {"Prayer",
       "Pour forth, we beseech thee, O Lord, thy grace into our hearts; that we, to whom the Incarnation of Christ, thy Son, was made known by the message of an angel, may by his Passion and Cross be brought to the glory of his Resurrection. Through the same Christ our Lord. Amen."},
    visit_this_house:
      {"Prayer",
       "Visit, we beseech thee, O Lord, this dwelling, and drive far from it all the snares of the enemy; let thy holy angels dwell herein to preserve us in peace; and may thy blessing be upon us always. Through Christ our Lord. Amen."},
    easter_collect:
      {"Prayer",
       "O God, who gave joy to the world through the Resurrection of thy Son, our Lord Jesus Christ; grant, we beseech thee, that through the intercession of the Virgin Mary, his Mother, we may obtain the joys of everlasting life. Through the same Christ our Lord. Amen."}
  }

  def text(key), do: @prayers |> Map.fetch!(key) |> elem(1)
  def title(key), do: @prayers |> Map.fetch!(key) |> elem(0)

  @doc """
  The midday prayer: the Angelus, or the Regina Caeli in Easter Time, as
  `%{title, lines: [{"V" | "R" | nil, text}]}`.
  """
  def midday(:easter) do
    %{
      title: "Regina Caeli",
      lines: [
        {"V", "Queen of Heaven, rejoice, alleluia."},
        {"R", "For He whom thou didst merit to bear, alleluia."},
        {"V", "Has risen as He said, alleluia."},
        {"R", "Pray for us to God, alleluia."},
        {"V", "Rejoice and be glad, O Virgin Mary, alleluia."},
        {"R", "For the Lord has truly risen, alleluia."},
        {nil, "Let us pray. " <> text(:easter_collect)}
      ]
    }
  end

  def midday(_season) do
    hail_mary = {nil, text(:hail_mary)}

    %{
      title: "The Angelus",
      lines: [
        {"V", "The Angel of the Lord declared unto Mary."},
        {"R", "And she conceived of the Holy Spirit."},
        hail_mary,
        {"V", "Behold the handmaid of the Lord."},
        {"R", "Be it done unto me according to thy word."},
        hail_mary,
        {"V", "And the Word was made flesh."},
        {"R", "And dwelt among us."},
        hail_mary,
        {"V", "Pray for us, O holy Mother of God."},
        {"R", "That we may be made worthy of the promises of Christ."},
        {nil, "Let us pray. " <> text(:pour_forth)}
      ]
    }
  end
end
